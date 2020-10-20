Function New-EC2SecurityGroupFromAWSPublicIpAddressRange
{
    [OutputType([Amazon.EC2.Model.SecurityGroup])]
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

        [Parameter(Mandatory=$False)]
        [ValidateSet(
            "Ipv4",
            "Ipv6"
        )]
        [string]$IpAddressFormat,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$GroupName,
        
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,
        
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$VpcId,
        
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$IpProtocol,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [int]$FromPort,
        
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [int]$ToPort
    )

    Begin
    {
        Set-DefaultAWSRegion -Region $Region -Scope Script
        Import-Module -Name AWS.Tools.EC2

        $Tags = @{ Key="Name"; Value=$GroupName }
        $NameTag = New-Object -TypeName Amazon.EC2.Model.TagSpecification
        $NameTag.ResourceType = "security-group"
        $NameTag.Tags.Add($Tags)

        $SgParams = @{
            GroupName = $GroupName
            Description = $Description
            VpcId = $VpcId
            TagSpecification = $NameTag
        }
        $GroupId = New-EC2SecurityGroup @SgParams
        $Ipv4Ranges = @()
        $Ipv6Ranges = @()
    }

    Process
    {
        $AWSPublicIpAddresses = Get-AWSPublicIpAddressRange -ServiceKey $ServiceKey -Region $Region

        ForEach($AWSPublicIpAddress In $AWSPublicIpAddresses)
        {
            If ($AWSPublicIpAddress.IpPrefix -like "*.*")
            {
                $Ipv4Range = New-Object -TypeName Amazon.EC2.Model.IpRange
                $Ipv4Range.CidrIp = $AWSPublicIpAddress.IpPrefix
                $ipv4Range.Description = $AWSPublicIpAddress.Service
                $Ipv4Ranges += $Ipv4Range
            }

            If ($AWSPublicIpAddress.IpPrefix -like "*:*")
            {
                $Ipv6Range = New-Object -TypeName Amazon.EC2.Model.Ipv6Range
                $Ipv6Range.CidrIpv6 = $AWSPublicIpAddress.IpPrefix
                $ipv6Range.Description = $AWSPublicIpAddress.Service
                $Ipv6Ranges += $Ipv6Range
            }
        }

    }
    
    End
    {
        $IpPermission = New-Object -TypeName Amazon.EC2.Model.IpPermission
        $IpPermission.IpProtocol = $IpProtocol
        $IpPermission.FromPort = $FromPort
        $IpPermission.ToPort = $ToPort
        $IpPermission.Ipv4Ranges = $Ipv4Ranges
        $IpPermission.Ipv6Ranges = $Ipv6Ranges

        If ( $IpAddressFormat -eq "Ipv4" )
        {
            $IpPermission.Ipv6Ranges.Clear()
        }
        ElseIf ( $IpAddressFormat -eq "Ipv6" )
        {
            $IpPermission.Ipv4Ranges.Clear()
        }

        Grant-EC2SecurityGroupIngress -GroupId $GroupId -IpPermission $IpPermission
    }
}

# Example
$IpPermissionParams = @{
    Region = "ap-northeast-1"
    ServiceKey = "S3", "CLOUD9"
    IpAddressFormat = "Ipv4"
    GroupName = "test-secgrp-01"
    Description = "test-secgrp-01"
    VpcId = "vpc-00000000000000000"
    IpProtocol = "tcp"
    FromPort = 80
    ToPort = 80
 }

New-EC2SecurityGroupFromAWSPublicIpAddressRange @IpPermissionParams

Get-Variable | Remove-Variable -ErrorAction SilentlyContinue