Set-DefaultAWSRegion -Region "ap-northeast-1" -Scope Script
Import-Module -Name AWS.Tools.EC2

# ------------------------------------
#  Name タグ設定用の関数
# ------------------------------------

Function New-EC2NameTag
{
    [OutputType([System.Object])]
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceType,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$TagValue
    )

    $Tag = @{ Key="Name"; Value=$TagValue }
    $Obj = New-Object -TypeName Amazon.EC2.Model.TagSpecification
    $Obj.ResourceType = $ResourceType
    $Obj.Tags.Add($Tag)
    return $Obj
}

# ------------------------------------
#  フィルタ作成用の関数
# ------------------------------------

Function New-EC2Filter
{
    [OutputType([System.Object])]
    [CmdletBinding()]    
    Param
    (
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Values
    )

    $Obj = New-Object -TypeName Amazon.EC2.Model.Filter
    $Obj.Name = $Name
    $Obj.Values = @($Values)
    return $Obj
}

# ------------------------------------
#  VPC の作成
# ------------------------------------

$CidrBlock = "10.0.0.0/16"
$VpcName = "vpc-01"
$VpcTag = New-EC2NameTag -ResourceType "vpc" -TagValue $VpcName
$VpcTagFilter = New-EC2Filter -Name "tag:Name" -Values $VpcName

If( -not (Get-EC2Vpc -Filter $VpcTagFilter))
{
    $TargetVpc = New-EC2Vpc -CidrBlock $CidrBlock -InstanceTenancy default -TagSpecification $VpcTag
    $TargetVpcId = $TargetVpc.VpcId
}
Else
{
    throw "${VpcName}: すでに存在する名前です。"
}

Edit-EC2VpcAttribute -VpcId $TargetVpcId -EnableDnsSupport $True
Edit-EC2VpcAttribute -VpcId $TargetVpcId -EnableDnsHostname $True

# ------------------------------------
#  サブネットの作成
# ------------------------------------

$Subnets = [ordered]@{
    "subnet-pub-a" = "10.0.0.0/24";
    "subnet-pub-c" = "10.0.1.0/24";
    "subnet-pri-a" = "10.0.2.0/24";
    "subnet-pri-c" = "10.0.3.0/24";
}

$SubnetTag = New-Object -TypeName Amazon.EC2.Model.TagSpecification
$SubnetTag.ResourceType = "subnet"

ForEach($Subnet In $Subnets.GetEnumerator())
{
    $SubnetTagFilter = New-EC2Filter -Name "tag:Name" -Values $Subnet.Key

    If( -not (Get-EC2Subnet -Filter $SubnetTagFilter))
    {
        $Tag = @{ Key="Name"; Value=$Subnet.Key }
        $SubnetTag.Tags.Add($Tag)

        If($Subnet.Key -match ".*-a$")
        {
            $AvailabilityZone = "ap-northeast-1a"
        }
        ElseIf($Subnet.Key -match ".*-c$")
        {
            $AvailabilityZone = "ap-northeast-1c"
        }
        Else
        {
            throw "$($Subnet.Key): サブネット名が条件外です。"
        }

        $SubnetParams = @{
            AvailabilityZone = $AvailabilityZone
            CidrBlock = $Subnet.Value
            VpcId = $TargetVpcId
            TagSpecification = $SubnetTag
        }
        New-EC2Subnet @SubnetParams

        $SubnetTag.Tags.Clear()
    }
    Else
    {
        throw "$($Subnet.Key): すでに存在する名前です。"
    }
}

# ------------------------------------
#  インターネットゲートウェイの作成
# ------------------------------------

$IgwName = "Igw-01"
$IgwTag = New-EC2NameTag -ResourceType "internet-gateway" -TagValue $IgwName
$IgwTagFilter = New-EC2Filter -Name "tag:Name" -Values $IgwName

If( -not (Get-EC2InternetGateway -Filter $IgwTagFilter))
{
    $TargetIgw = New-EC2InternetGateway -TagSpecification $IgwTag
    $TargetIgwId = $TargetIgw.InternetGatewayId
}
Else
{
    throw "${IgwName}: すでに存在する名前です。"
}

Add-EC2InternetGateway -VpcId $TargetVpcId -InternetGatewayId $TargetIgwId

# ------------------------------------
#  仮想プライベートゲートウェイの作成
# ------------------------------------

$VgwName = "vgw-01"
$VgwTag = New-EC2NameTag -ResourceType "vpn-gateway" -TagValue $VgwName
$IgwTagFilter = New-EC2Filter -Name "tag:Name" -Values $VgwName

If( -not (Get-EC2VpnGateway -Filter $VgwTagFilter))
{
    $TargetVgw = New-EC2VpnGateway -Type ipsec.1 -TagSpecification $VgwTag
    $TargetVgwId = $TargetVgw.VpnGatewayId
}
Else
{
    throw "${VgwName}: すでに存在する名前です。"
}

Add-EC2VpnGateway -VpcId $TargetVpcIdId -VpnGatewayId $TargetVgwId

# ------------------------------------
#  ルートテーブルの作成と設定
# ------------------------------------

$RtbNames = @("rtb-public-01", "rtb-private-01")
$VpcIdFilter = New-EC2Filter -Name "vpc-id" -Values $TargetVpcId

ForEach($RtbName In $RtbNames)
{
    $RtbTag = New-EC2NameTag -ResourceType "route-table" -TagValue $RtbName
    $RtbTagFilter = New-EC2Filter -Name "tag:Name" -Values $RtbName

    If( -not (Get-EC2RouteTable -Filter $RtbTagFilter))
    {
        $TargetRtb = New-EC2RouteTable -VpcId $TargetVpcId -TagSpecification $RtbTag
        $TargetRtbId = $TargetRtb.RouteTableId
    }
    Else
    {
        throw "${RtbName}: すでに存在する名前です。"
    }

    $PubSwitch = "*pub*"
    $PriSwitch = "*pri*"

    If($RtbName -like $PubSwitch)
    {
        New-EC2Route -RouteTableId $TargetRtbId -GatewayId $TargetIgwId -DestinationCidrBlock "0.0.0.0/0"
        $SwitchTagFilter = New-EC2Filter -Name "tag:Name" -Values $PubSwitch
        $PublicRtbId = $TargetRtbId
    }
    ElseIf($RtbName -like $PriSwitch)
    {
        New-EC2Route -RouteTableId $TargetRtbId -GatewayId $TargetVgwId -DestinationCidrBlock "0.0.0.0/0"
        $SwitchTagFilter = New-EC2Filter -Name "tag:Name" -Values $PriSwitch
        $PrivateRtbId = $TargetRtbId
    }
    Else
    {
        throw "${RtbName}: ルートテーブル名が条件外です。"
    }

    $TargetSubnets = (Get-EC2Subnet -Filter $VpcIdFilter, $SwitchTagFilter).SubnetId
    ForEach($TargetSubnet In $TargetSubnets)
    {
        Register-EC2RouteTable -RouteTableId $TargetRtbId -SubnetId $TargetSubnet
    }
}

$OldMainRtbAssoc = (Get-EC2RouteTable -Filter $VpcIdFilter).Associations | Where-Object -FilterScript { $_.Main }
$OldMainRtbId = $OldMainRtbAssoc.RouteTableId
$AssociationId = $OldMainRtbAssoc.RouteTableAssociationId
Set-EC2RouteTableAssociation -AssociationId $AssociationId -RouteTableId $PublicRtbId
Remove-EC2RouteTable -RouteTableId $OldMainRtbId -Force

# ------------------------------------
#  S3 への VPC エンドポイントの作成
# ------------------------------------

$EndPointName = "vpce-s3-get-all"
$EndPointTag = New-EC2NameTag -ResourceType "vpc-endpoint" -TagValue $EndPointName
$EndPointFilter = New-EC2Filter -Name "tag:Name" -Values $EndPointName
$ServiceName = "com.amazonaws.ap-northeast-1.s3"
$PolicyDocument = @'
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "*"
        }
    ]
}
'@

If( -not (Get-EC2VpcEndpoint -Filter $EndPointFilter))
{
    $EndPintParams = @{
        ServiceName = $ServiceName
        VpcId = $TargetVpcId
        RouteTableId = $PublicRtbId, $PrivateRtbId
        PolicyDocument = $PolicyDocument
        TagSpecification = $EndPointTag
    }
    New-EC2VpcEndpoint @EndPintParams
}
Else
{
    throw "${EndPointName}: すでに存在する名前です。"
}