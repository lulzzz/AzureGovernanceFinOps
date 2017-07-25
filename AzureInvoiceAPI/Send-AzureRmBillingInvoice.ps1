<# 
.SYNOPSIS
   This function gets the latest Subscription invoice object and sends it as an email attachment.

.DESCRIPTION
  This function gets the latest Subscription invoice object and sends it as an email attachment.
  The function passes the invoice Byte object it to a memory stream by using the DownloadData(Uri) method of the System.Net.WebClient .NET Framework class.
  This method, takes a URI as argument and returns a Byte array containing the downloaded resource.
  The method enables the sending of the invoice as an email attachment without having to save the file to a host machine directory.
  It can be deployed as a runbook to an Azure Automation account.
   
.PARAMETER SubscriptionName
        Subscription Name.

.PARAMETER ResourceGroupName
        ResourceGroupName.

.PARAMETER VaultName
        Key vault name that holds the credential secret.

.PARAMETER To
        To email address.

.EXAMPLE
       Send-AzureRmBillingInvoice
       
.FUNCTIONALITY
        PowerShell Language
/#>

Param(
$SubscriptionName = "Trial Subscription",
$ResourceGroupName = "RGXavier",
$VaultName = "vaultspr",
$smtpserver = "smtp.sendgrid.net",
$from = "jack.bauer@democonsults.com",
$to = "jon.hacker@democonsults.com",
$port = "587"
)

#endregion

#region
#Azure Logon
$connectionName = "AzureRunAsConnection"

try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
            }
    }
Select-AzureRmSubscription -SubscriptionName $SubscriptionName

#endregion

#region email creds
$SendGridSecretName = "SendGridPassword"
$sendgridusername = "azure_eb0fc2179dd8f386d4f4e1f60dc2aff1@azure.com"
[securestring]$emailpassword = ((Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SendGridSecretName).SecretValue)
$emailcred = (New-Object System.Management.Automation.PSCredential($sendgridusername, $emailpassword))

#endregion

#region
#Get Billing Invoice Object and create memory stream
$invoiceObject = Get-AzureRmBillingInvoice -Latest
$webClient = New-Object -TypeName System.Net.WebClient
[Byte[]] $invoice = $webClient.DownloadData($invoiceObject.DownloadUrl)

#Create memory stream
$memorystream = New-Object -TypeName System.IO.MemoryStream
$memorystream.Write($invoice,0,$invoice.Length)

#Set the position to the beginning of the stream
[void]$memorystream.Seek(0,'Begin')

#endregion

#region
#Prep Message Object
$message = New-Object System.Net.Mail.MailMessage 
$smtpClient = New-Object System.Net.Mail.smtpClient($smtpserver,$port)
$smtpClient.EnableSsl = $true
$smtpClient.Credentials = $emailcred
$recipient = New-Object System.Net.Mail.MailAddress($to)
$sender = New-Object System.Net.Mail.MailAddress($from)
$message.Sender = $sender
$message.From = $sender
$message.Subject = "AzureRm Billing Invoice"
$message.To.add($recipient)
$message.Body = "The AzureRm Billing Invoice is attached."

#endregion

#region
#Creat and add the attachment
 $contentType = New-Object -TypeName System.Net.Mime.ContentType -Property @{
 MediaType = [Net.Mime.MediaTypeNames+Application]::Octet
 Name = "Invoice.pdf"
 }
$attachment = New-Object Net.Mail.Attachment $memoryStream, $contentType
$message.Attachments.Add($attachment)

#endregion
             
#region
# Send Mail via SmtpClient 
$smtpClient.Send($message)

#endregion

#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls
 
