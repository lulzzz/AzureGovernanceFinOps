

<#
.SYNOPSIS
   Function to stop/start multiple VMs simultaneously
.DESCRIPTION
   This Azure Automation function uses the awesome Invoke-Parallel Powershell Function from Cookie.Monster to automate simultaneous VMs shutdown/start.
   https://github.com/RamblingCookieMonster/Invoke-Parallel 
   The Invoke-Parallel function is imported as a module. The VM(s) array is passed to the Invoke-Parallel module which then execute my function in a script block.
   Multiple runspaces/threads are created based on the number of VMs to be set to Start or Stop. Based on my tests, using the Invoke-Parallel function is faster than using Foreach -Parallel in a workflow.
   The function can be deployed as Runbook and triggered by a set schedule or a webhook. It can take a Resource Group name or csv file of Virtual Machines as parameters.
   An email notification is sent to the Subscription Admin after execution.
.PARAMETER SubscriptionName
        Subscription to be processed.
.PARAMETER Path
        The path parameter takes the path to a csv files that contains the list of VMs and ResourceGroupNames to be shutdown. It cannot be used with the ResourceGroupName parameter.
.PARAMETER ResourceGroupName
        ResourceGroupName of the VMs to be shutdown. It cannot be used with the Path parameter.
.PARAMETER State
        Power State that determines if VM(s) are to be shutdown or started. Valid values are Stop and Start.
.EXAMPLE
        Set-VMPowerState -FilePath "C:\MeterRates\VSProtestvms.csv" -State Stop -SubscriptionName "Trial"

            Runs against a csv file specified with the FilePath parameter
.EXAMPLE
        Set-VMPowerState -ResourceGroupName RGXavier -State Stop -SubscriptionName "Trial"

            Runs against a ResourceGroupName specified with the ResourceGroupName parameter
.FUNCTIONALITY
        PowerShell Language
#>

[CmdletBinding()]

param(
    [parameter(Mandatory = $false)]
    [string]$SubscriptionName = "Free Trial",
    [parameter(Mandatory = $false)]
    [string]$FilePath,
    [parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "RGManagedDisks",
    [parameter(Mandatory = $false)]
    [ValidateSet("Start", "Stop")]
    [ValidateNotNullOrEmpty()]
    [string]$State = "Stop"
       
)

Write-Host "Started at" (Get-Date)
$WarningPreference = "SilentlyContinue"

#region Azure Logon
try {
    # Get the connection "AzureRunAsConnection "
    $connectionName = "AzureRunAsConnection"
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
Select-AzureRmSubscription -SubscriptionName $SubscriptionName

#endregion

#region create email creds
$Smtpserver = "smtp.sendgrid.net"
$From = "chris.hansen@spr.com"
$To = "charles.chukwudozie@spr.com"
$VaultName = "vaultspr"
$SecretName = "SendgridPassword"
$Port = "587"
$sendgridusername = "azure_eb0fc2179dd8f386d4f4e1f60dc2aff1@azure.com"
$sendgridPassword = (Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SecretName).SecretValueText
$emailpassword = ConvertTo-SecureString -String $sendgridPassword -AsPlainText -Force
$emailcred = New-Object System.Management.Automation.PSCredential($sendgridusername, $emailpassword)
#endregion

#region
$currentWeekDay = (Get-Date).ToUniversalTime().ToString("dddd")
if ($FilePath) {
    if ($State -eq "Stop") {
        $vms = Import-Csv -Path $FilePath | Get-AzureRmVM -Status | ? {$_.Statuses[1].DisplayStatus -eq "vm running"}
        Write-Host "Shutting down VM(s) today .." $currentWeekDay
            
        $results = $vms | Invoke-Parallel -NoCloseOnTimeout -ScriptBlock {
            $stopStatus = Stop-AzureRmVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Force -Verbose
            if ($stopStatus.Status -eq "Succeeded") {
                $vmstatus = Get-AzureRmVM -Status -ResourceGroupName $_.ResourceGroupName -Name $_.Name -WarningAction SilentlyContinue
                $vmstatus
            }
        }              
    }
    else {
        $vms = Import-Csv -Path $FilePath | Get-AzureRmVM -Status | ? {$_.Statuses[1].DisplayStatus -ne "vm running"}
        Write-Host "Starting up VM(s) today .." $currentWeekDay                
        $results = $vms | Invoke-Parallel -NoCloseOnTimeout -ScriptBlock {
            $startStatus = Start-AzureRmVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Verbose
            if ($startStatus.Status -eq "Succeeded") {
                $vmstatus = Get-AzureRmVM -Status -ResourceGroupName $_.ResourceGroupName -Name $_.Name -WarningAction SilentlyContinue
                $vmstatus
            }
        }
    }
}
elseif ($resourceGroupName) {
    if ($State -eq "Stop") {
        $vms = Get-AzureRmVM -Status -ResourceGroupName $ResourceGroupName | ? {$_.PowerState -eq "vm running"}
        Write-Host "Shutting down VM(s) today .." $currentWeekDay            
        $results = $vms | Invoke-Parallel -NoCloseOnTimeout -ScriptBlock {
            $stopStatus = Stop-AzureRmVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Force -Verbose
            if ($stopStatus.Status -eq "Succeeded") {
                $vmstatus = $_.ToPSVirtualMachine() | Get-AzureRmVM -Status
                $vmstatus
            }
        }             
    }
    else {
        $vms = Get-AzureRmVM -Status -ResourceGroupName $ResourceGroupName | ? {$_.PowerState -ne "vm running"}
        Write-Host "Starting up VM(s) today .." $currentWeekDay
                
        $results = $vms | Invoke-Parallel -NoCloseOnTimeout -ScriptBlock {
            $startStatus = Start-AzureRmVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Verbose
            if ($startStatus.Status -eq "Succeeded") {
                $vmstatus = $_.ToPSVirtualMachine() | Get-AzureRmVM -Status
                $vmstatus
            }
        }
    }
}
else {
    "Please enter a value for FilePath or ResourceGroupName"
}

$results | ft @{"Label" = "Status"; e = {$_.Statuses[1].DisplayStatus}}, Name, ResourceGroupName

#endregion

#region process email

$a = "<style>"
$a = $a + "BODY{background-color:white;}"
$a = $a + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
$a = $a + "TH{border-width: 1px;padding: 10px;border-style: solid;border-color: black;}"
$a = $a + "TD{border-width: 1px;padding: 10px;border-style: solid;border-color: black;}"
$a = $a + "</style>"
$body = ""
$body += "<BR>"
$body += "These" + " " + ($results.count) + " " + "Azure VM(s) were just shutdown successfully. Thank you."
$body += "<BR>"
$body += $results | Select-Object -Property @{"Label" = "Status"; e = {$_.Statuses[1].DisplayStatus}}, Name, ResourceGroupName | ConvertTo-Html -Head $a
$body = $body |Out-String
$subject = "These Azure VMs have been successfully shutdown."
if ($results -ne $null) {
    Send-MailMessage -Body $body `
        -BodyAsHtml `
        -SmtpServer $smtpserver `
        -From $from `
        -Subject $subject `
        -To $to `
        -Port $port `
        -Credential $emailcred `
        -UseSsl
}
#endregion
Write-Host "Completed at " (Get-Date)
#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue