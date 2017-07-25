<# 

.SYNOPSIS
   Function to remediate untagged resources and resources with non standard tags.
.DESCRIPTION
   Function to remediate untagged resources and resources with non standard tags.
   The script is currently associated with a test subscription.A Service Principal is used to process Azure Subscription authentication.
   Dot source this function into a PowerShell console:"PS C:\Scripts> . C:\myscripts\Functions\Set-ResourceTagsv2.ps1" to run it directly.
.PARAMETER SubscriptionID
        Subscription ID to be processed.
.PARAMETER TenantId
        TenantId of subscription to be processed.
.PARAMETER ServiceUri
        Application ID of the Service Principal(assigned Contributor role) to be used for auto logon and generating the access token.
        Can be retrieved by using the Get-AzureADApplication, Get-AzureRmADApplication or Get-AzureRmADServicePrincipal.
.PARAMETER ServicePassword
        The password/client key of the Service Principal generated from the AzureAD portal App Registrations/Key blade.
       Run against a test subscription.
.FUNCTIONALITY
        PowerShell Language
/#>

param(
            [parameter(Mandatory=$false)]
            [string]$resourceGroupName = "Xavierrg",
            $subscriptionID = "4d8974d9-2d78-4838-ad15-92c5e4f65f65",
            $TenantId = "87ff4425-8172-46ec-b396-e5c3d3405e9d",
            $ServiceUri = "526fa2c4-7476-4445-aa7e-ecca0bd67f11",
            $ServicePassword = "ZcEGbDgLgp+yrbW3NdDfEWvkcMaDn4jNEC0E7MYVItY="
        )

#region Azure PowerShell login
Write-Host "started at" (Get-Date)
$Password = ConvertTo-SecureString $ServicePassword -AsPlainText -Force
$psCred = New-Object System.Management.Automation.PSCredential($ServiceUri, $Password)
Add-AzureRmAccount -Credential $psCred -TenantId $TenantId -ServicePrincipal | Out-Null
$subscription = Select-AzureRmSubscription -SubscriptionId $subscriptionID
#endregion

#region Check for wrong tags and values. apply correct tags using csv file data.
#$DebugPreference = "Continue"
$tagsCsv = Import-Csv -Path C:\MeterRates\NielsenRemediationTags.csv
$goodTags = ($tagsCsv | Get-Member -MemberType NoteProperty).Name
$standardTags = @{CreatedBy = "admin@democonsults.net"
             ServerRole = ""
             Environment = ""
             ApplicationName= ""
             Department = ""
             CostCenter = ""
             Description = ""}
$unTaggedResources = Get-AzureRmResource |?{($_.ResourceGroupName -eq $resourceGroupName) -and ($_.Tags.Count -eq 0)}
$taggedResources = Get-AzureRmResource | ?{($_.ResourceGroupName -eq $resourceGroupName) -and ($_.Tags.Count -ge 1)}
          if($unTaggedResources -ne $null){
          $i = 0         
          foreach($unTaggedresource in $unTaggedResources){
          $i++
          Write-Progress -Activity "Remediating Untagged Resources..." -Status "Progress:" -PercentComplete ($i/$unTaggedresources.count * 100)
                $discardOutput = Set-AzureRmResource -ResourceId $unTaggedresource.ResourceId -Tag $standardTags -Force                                                             
            }
        }
            
          if($taggedResources -ne $null){
          $i = 0
          foreach($taggedResource in $taggedResources){
          $i++
          Write-Progress -Activity "Remediating Tagged Resources..." -Status "Progress:" -PercentComplete ($i/$taggedResources.count * 100)
                foreach($goodTag in $goodTags){
                    if(!($taggedResource.Tags.ContainsKey($goodTag))){ 
                    $tags=$taggedResource.Tags
                    $tags.Add($goodTag,$null)
                    $discardOutput = Set-AzureRmResource -ResourceId $taggedResource.ResourceId -Tag $tags -Force
                   }

                    foreach($badTag in $tagsCsv.$goodTag){
                        if($taggedResource.Tags.ContainsKey($badTag)) {
                    $replacementTagValue = $taggedResource.Tags.$badTag
                    $replacementTag = $goodtag
                    $btags=$taggedResource.Tags
                    $btags.Remove($badTag)
                    $btags.Remove($goodTag)
                    $btags.Add($replacementTag,$replacementTagValue)
                    $discardOutput = Set-AzureRmResource -ResourceId $taggedResource.ResourceId -Tag $btags -Force
                   }                        
                }
            }
          
          }
        }

            
            
               
#endregion

Write-Host "finished at" (Get-Date)
#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls
            
 

            
        
    
 