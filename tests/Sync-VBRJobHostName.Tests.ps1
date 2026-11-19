# Sync-VBRJobHostName.Tests.ps1
# Unit tests for the host-name casing rewrite applied to job import payloads.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Sync-VBRJobHostName.ps1')
    . (Join-Path $PSScriptRoot '..' 'VbrMigrationAutomation' 'Private' 'Get-VBRPaginatedData.ps1')

    function New-JobPayload {
        @'
{
  "jobs": [{
    "name": "Job-01",
    "virtualMachines": {
      "includes": [
        { "type": "VirtualMachine", "hostName": "esxi-01.contoso.local", "name": "App-01",
          "objectId": "11", "urn": "esx:esxi-01.contoso.local;vm:11" },
        { "type": "Host", "hostName": "esxi-01.contoso.local", "name": "esxi-01.contoso.local",
          "objectId": "esxi-01.contoso.local", "urn": "esx:esxi-01.contoso.local" }
      ],
      "excludes": { "disks": [ { "vmObject": { "type": "VirtualMachine", "hostName": "esxi-01.contoso.local",
          "name": "App-01", "objectId": "11", "urn": "esx:esxi-01.contoso.local;vm:11" } } ] }
    },
    "storage": { "backupRepository": { "name": "Repo-01" } }
  }]
}
'@ | ConvertFrom-Json -Depth 20
    }
}

Describe 'Update-VBRHostNameCasing' {
    It 'rewrites hostName, URN and host-object name/objectId to the target casing' {
        $p = New-JobPayload
        $changes = Update-VBRHostNameCasing -Node $p -HostNames @('ESXi-01.contoso.local')

        $vm   = $p.jobs[0].virtualMachines.includes[0]
        $esxi = $p.jobs[0].virtualMachines.includes[1]
        $disk = $p.jobs[0].virtualMachines.excludes.disks[0].vmObject

        $vm.hostName   | Should -BeExactly 'ESXi-01.contoso.local'
        $vm.urn        | Should -BeExactly 'esx:ESXi-01.contoso.local;vm:11'
        $esxi.name     | Should -BeExactly 'ESXi-01.contoso.local'
        $esxi.objectId | Should -BeExactly 'ESXi-01.contoso.local'
        $esxi.urn      | Should -BeExactly 'esx:ESXi-01.contoso.local'
        $disk.urn      | Should -BeExactly 'esx:ESXi-01.contoso.local;vm:11'
        $changes       | Should -Be @('esxi-01.contoso.local -> ESXi-01.contoso.local')
    }

    It 'leaves VM names and object IDs alone' {
        $p = New-JobPayload
        Update-VBRHostNameCasing -Node $p -HostNames @('ESXi-01.contoso.local', 'APP-01') | Out-Null
        $p.jobs[0].virtualMachines.includes[0].name     | Should -BeExactly 'App-01'
        $p.jobs[0].virtualMachines.includes[0].objectId | Should -BeExactly '11'
        $p.jobs[0].storage.backupRepository.name        | Should -BeExactly 'Repo-01'
    }

    It 'changes nothing when the casing already matches' {
        $p = New-JobPayload
        Update-VBRHostNameCasing -Node $p -HostNames @('esxi-01.contoso.local') | Should -BeNullOrEmpty
    }

    It 'changes nothing for hosts the target does not know' {
        $p = New-JobPayload
        Update-VBRHostNameCasing -Node $p -HostNames @('vcenter.other.local') | Should -BeNullOrEmpty
        $p.jobs[0].virtualMachines.includes[0].hostName | Should -BeExactly 'esxi-01.contoso.local'
    }

    It 'handles an empty inventory' {
        $p = New-JobPayload
        Update-VBRHostNameCasing -Node $p -HostNames @() | Should -BeNullOrEmpty
    }
}

Describe 'Sync-VBRJobHostName' {
    BeforeEach { Mock Write-Host { } }

    It 'uses the names from the target inventory' {
        Mock Invoke-RestMethod { [pscustomobject]@{ data = @([pscustomobject]@{ name = 'ESXi-01.contoso.local' }) } }
        $p = New-JobPayload
        Sync-VBRJobHostName -Connection ([pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{} }) -Payload $p
        $p.jobs[0].virtualMachines.includes[0].urn | Should -BeExactly 'esx:ESXi-01.contoso.local;vm:11'
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -like 'https://t/api/v1/inventory/vmware/hosts?skip=0*' }
    }

    It 'warns and leaves the payload unchanged when the inventory call fails' {
        Mock Invoke-RestMethod { throw 'boom' }
        Mock Write-Warning { }
        $p = New-JobPayload
        Sync-VBRJobHostName -Connection ([pscustomobject]@{ BaseUri = 'https://t/api/v1'; Headers = @{} }) -Payload $p
        $p.jobs[0].virtualMachines.includes[0].hostName | Should -BeExactly 'esxi-01.contoso.local'
        Should -Invoke Write-Warning -Times 1
    }
}
