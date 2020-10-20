Function New-EC2ManagedPrefixListFromAWSPublicIpAddressRange
{
    [OutputType([Amazon.EC2.Model.PrefixList])]
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$True)]
        [ValidateSet(
            "af-south-1",
            "ap-east-1",
            "ap-northeast-1",
            "ap-northeast-2",
            "ap-south-1",
            "ap-southeast-1",
            "ap-southeast-2",
            "ca-central-1",
            "eu-central-1",
            "eu-north-1",
            "eu-south-1",
            "eu-west-1",
            "eu-west-2",
            "eu-west-3",
            "me-south-1",
            "sa-east-1",
            "us-east-1",
            "us-east-2",
            "us-west-1",
            "us-west-2",
            "us-iso-east-1",
            "us-isob-east-1"
        )]
        [string]$Region,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ServiceKey,

        [Parameter(Mandatory=$True)]
        [ValidateSet(
            "Ipv4",
            "Ipv6"
        )]
        [string]$IpAddressFormat,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $MaxEntry,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $PrefixListName
    )

    Begin
    {
        Set-DefaultAWSRegion -Region $Region -Scope Script
        Import-Module -Name AWS.Tools.EC2

        $Tags = @{ Key="Name"; Value=$PrefixListName }
        $NameTag = New-Object -TypeName Amazon.EC2.Model.TagSpecification
        $NameTag.ResourceType = "prefix-list"
        $NameTag.Tags.Add($Tags)

        $Ipv4Entries = @()
        $Ipv6Entries = @()
    }

    Process
    {
        $AWSPublicIpAddresses = Get-AWSPublicIpAddressRange -ServiceKey $ServiceKey -Region $Region

        ForEach($AWSPublicIpAddress In $AWSPublicIpAddresses)
        {
            If ($AWSPublicIpAddress.IpPrefix -like "*.*" -and $IpAddressFormat -eq "Ipv4")
            {
                $Ipv4Entry = New-Object -TypeName Amazon.EC2.Model.AddPrefixListEntry
                $Ipv4Entry.Cidr = $AWSPublicIpAddress.IpPrefix
                $Ipv4Entry.Description = $AWSPublicIpAddress.Service
                $Ipv4Entries += $Ipv4Entry
            }

            If ($AWSPublicIpAddress.IpPrefix -like "*:*" -and $IpAddressFormat -eq "Ipv6")
            {
                $Ipv6Entry = New-Object -TypeName Amazon.EC2.Model.AddPrefixListEntry
                $Ipv6Entry.Cidr = $AWSPublicIpAddress.IpPrefix
                $Ipv6Entry.Description = $AWSPublicIpAddress.Service
                $Ipv6Entries += $Ipv6Entry
            }
        }
    }
    
    End
    {
        $PrefixListParams = @{
            AddressFamily = $IpAddressFormat
            MaxEntry = $MaxEntry
            PrefixListName = $PrefixListName
            TagSpecification = $NameTag
        }

        If ($IpAddressFormat -eq "Ipv4")
        {
            $PrefixListParams.Add("Entry", $Ipv4Entries)
        }

        If ($IpAddressFormat -eq "Ipv6")
        {
            $PrefixListParams.Add("Entry", $Ipv6Entries)
        }

        New-EC2ManagedPrefixList @PrefixListParams
    }
}

# Example
$Params = @{
    Region = "ap-northeast-1"
    ServiceKey = "S3", "AMAZON_CONNECT"
    IpAddressFormat = "Ipv4"
    MaxEntry = 30
    PrefixListName = "test-prefix-01"
 }

New-EC2ManagedPrefixListFromAWSPublicIpAddressRange @Params

Get-Variable | Remove-Variable -ErrorAction SilentlyContinue

