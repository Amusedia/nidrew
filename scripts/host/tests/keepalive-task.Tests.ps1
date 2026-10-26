# Pester 3.4 tests for scripts/host/keepalive-task.ps1. They build task
# definitions in memory and never register, start, or stop tasks.
#   powershell -ExecutionPolicy Bypass -Command "Invoke-Pester scripts\host\tests"

$script = Join-Path $PSScriptRoot '..\keepalive-task.ps1'
. $script

$userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name

function New-TestTask {
    param(
        [string]$Distribution = 'Debian',
        [string]$LinuxUser = 'nidrew',
        [string]$Description = $KeepaliveMarker
    )
    $task = New-KeepaliveTask -Distribution $Distribution -LinuxUser $LinuxUser -UserId $userId
    $task.Description = $Description
    $task
}

Describe 'New-KeepaliveTask' {
    $task = New-TestTask
    $summary = ConvertTo-KeepaliveSummary $task

    It 'runs sleep infinity as the Linux user in the distribution without a window' {
        $summary.Execute | Should Be "$env:SystemRoot\System32\conhost.exe"
        $summary.Arguments | Should Be "--headless $env:SystemRoot\System32\wsl.exe --distribution Debian --user nidrew --exec sleep infinity"
        $summary.ActionCount | Should Be 1
    }
    It 'triggers only at the owning user''s logon' {
        $summary.TriggerCount | Should Be 1
        $summary.TriggerType | Should Be 'MSFT_TaskLogonTrigger'
        $summary.TriggerUser | Should Be $summary.UserId
    }
    It 'runs as the owning user, interactive, without elevation' {
        $summary.UserId | Should Be ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        $summary.LogonType | Should Be 'Interactive'
        $summary.RunLevel | Should Be 'Limited'
    }
    It 'runs indefinitely, once, on any power source, without restarting' {
        $summary.ExecutionTimeLimit | Should Be 'PT0S'
        $summary.MultipleInstances | Should Be 'IgnoreNew'
        $summary.DisallowStartIfOnBatteries | Should Be $false
        $summary.StopIfGoingOnBatteries | Should Be $false
        $summary.RunOnlyIfIdle | Should Be $false
        $summary.StopOnIdleEnd | Should Be $false
        $summary.WakeToRun | Should Be $false
        $summary.RestartCount | Should Be 0
        $summary.Enabled | Should Be $true
    }
    It 'rejects names that would need quoting' {
        { New-KeepaliveTask -Distribution 'De bian' -LinuxUser nidrew -UserId $userId } | Should Throw
        { New-KeepaliveTask -Distribution Debian -LinuxUser 'a"b' -UserId $userId } | Should Throw
    }
}

Describe 'Get-KeepaliveTaskState' {
    $desired = ConvertTo-KeepaliveSummary (New-TestTask)

    It 'reports a missing task' {
        (Get-KeepaliveTaskState $null $desired).State | Should Be 'missing'
    }
    It 'reports a matching task' {
        (Get-KeepaliveTaskState (New-TestTask) $desired).State | Should Be 'matching'
    }
    It 'reports a managed task with other settings as outdated, naming the fields' {
        $result = Get-KeepaliveTaskState (New-TestTask -LinuxUser root) $desired
        $result.State | Should Be 'outdated'
        $result.Differences | Should Be 'Arguments'
    }
    It 'reports a task without the marker as a conflict' {
        $result = Get-KeepaliveTaskState (New-TestTask -Description 'my own keepalive') $desired
        $result.State | Should Be 'conflict'
    }
    It 'reports a managed task owned by another user as a conflict' {
        $other = ConvertTo-KeepaliveSummary (New-TestTask)
        $other.UserId = 'S-1-5-21-1-2-3-4'
        $other.TriggerUser = 'S-1-5-21-1-2-3-4'
        (Get-KeepaliveTaskState (New-TestTask) $other).State | Should Be 'conflict'
    }
}

Describe 'Test-KeepaliveProcess' {
    It 'matches the conhost and wsl.exe processes of the task' {
        Test-KeepaliveProcess 'conhost.exe' '"C:\Windows\System32\conhost.exe" --headless C:\Windows\System32\wsl.exe --distribution Debian --user nidrew --exec sleep infinity' Debian nidrew | Should Be $true
        Test-KeepaliveProcess 'wsl.exe' 'C:\Windows\System32\wsl.exe --distribution Debian --user nidrew --exec sleep infinity' Debian nidrew | Should Be $true
    }
    It 'ignores other distributions, users, commands, and programs' {
        Test-KeepaliveProcess 'wsl.exe' 'wsl.exe --distribution Ubuntu --user nidrew --exec sleep infinity' Debian nidrew | Should Be $false
        Test-KeepaliveProcess 'wsl.exe' 'wsl.exe --distribution Debian --user root --exec sleep infinity' Debian nidrew | Should Be $false
        Test-KeepaliveProcess 'wsl.exe' 'wsl.exe --distribution Debian --user nidrew --exec sleep 10' Debian nidrew | Should Be $false
        Test-KeepaliveProcess 'cmd.exe' 'cmd.exe /c wsl.exe --distribution Debian --user nidrew --exec sleep infinity' Debian nidrew | Should Be $false
        Test-KeepaliveProcess 'wsl.exe' $null Debian nidrew | Should Be $false
    }
}
