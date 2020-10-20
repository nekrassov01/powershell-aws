Set-DefaultAWSRegion -Region "ap-northeast-1" -Scope Script
Import-Module -Name AWS.Tools.EC2, AWS.Tools.IdentityManagement

# ------------------------------------
#  Name タグ設定用の関数
# ------------------------------------

Function New-EC2NameTag
{
    [OutputType([Amazon.EC2.Model.TagSpecification])]
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
    [OutputType([Amazon.EC2.Model.Filter])]
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
#  IPv4 許可設定用の関数
# ------------------------------------

Function New-EC2Ipv4Range
{
    [OutputType([Amazon.EC2.Model.IpPermission])]
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$CidrIp,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

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

    $IpRange = New-Object -TypeName Amazon.EC2.Model.IpRange
    $IpRange.CidrIp = $CidrIp
    $IpRange.Description = $Description
    $IpPermission = New-Object -TypeName Amazon.EC2.Model.IpPermission
    $IpPermission.IpProtocol = $IpProtocol
    $IpPermission.FromPort = $FromPort
    $IpPermission.ToPort = $ToPort
    $IpPermission.Ipv4Ranges.Add($IpRange)
    return $IpPermission
}

# ------------------------------------
#  EBS 設定用の関数
# ------------------------------------

Function New-EC2BlockDevice
{
    [OutputType([Amazon.EC2.Model.BlockDeviceMapping])]
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [int]$VolumeSize,

        [Parameter(Mandatory=$True)]
        [ValidateSet("Gp2", "Io1", "Io2", "Sc1", "St1", "Standard")]
        [Amazon.EC2.VolumeType]$VolumeType,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [bool]$DeleteOnTermination = $true,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceName = "/dev/xvda"
    )

    $BlockDevice = New-Object -TypeName Amazon.EC2.Model.EbsBlockDevice
    $BlockDevice.VolumeSize = $VolumeSize
    $BlockDevice.VolumeType = $VolumeType
    $BlockDevice.DeleteOnTermination = $DeleteOnTermination
    $BlockDeviceMapping = New-Object -TypeName Amazon.EC2.Model.BlockDeviceMapping
    $BlockDeviceMapping.DeviceName = $DeviceName
    $BlockDeviceMapping.Ebs = $BlockDevice
    return $BlockDeviceMapping
}

# ------------------------------------
#  対象VPC/サブネットの情報を取得
# ------------------------------------

$VpcName = "vpc-01"
$VpcTagFilter = New-EC2Filter -Name "tag:Name" -Values $VpcName
$TargetVpcId = (Get-EC2Vpc -Filter $VpcTagFilter).VpcId

$SubnetName = "subnet-pub-a"
$SubnetTagFilter = New-EC2Filter -Name "tag:Name" -Values $SubnetName
$TargetSubnetId = (Get-EC2Subnet -Filter $SubnetTagFilter).SubnetId

# ------------------------------------
#  Amiの取得
# ------------------------------------

$AmiFilter = New-EC2Filter -Name "name" -Values "amzn2-ami-hvm-*-x86_64-gp2"
$TargetAmi = @(Get-EC2Image -Filter $AmiFilter | Sort-Object -Property "CreationDate" -Descending)[0]
$TargetAmiId = $TargetAmi.ImageId

# ------------------------------------
#  セキュリティグループの作成
# ------------------------------------

$SgName = "sec-01"
$SgTag = New-EC2NameTag -ResourceType "security-group" -TagValue $SgName
$SgTagFilter = New-EC2Filter -Name "tag:Name" -Values $SgName

$IpRangeObjects = @{
    IpPermission1 = @{
        CidrIp = "0.0.0.0/0"
        IpProtocol = "tcp"
        FromPort = 443
        ToPort = 443
        Description = "https: all"
    }
    IpPermission2 = @{
        CidrIp = "111.111.111.111/32"
        IpProtocol = "tcp"
        FromPort = 80
        ToPort = 80
        Description = "http: my-gip"
    }
     IpPermission3 = @{
        CidrIp = "111.111.111.111/32"
        IpProtocol = "tcp"
        FromPort = 22
        ToPort = 22
        Description = "ssh: my-gip"
    }
    IpPermission4 = @{
        CidrIp = "111.111.111.111/32"
        IpProtocol = "icmp"
        FromPort = -1
        ToPort = -1
        Description = "icmp: my-gip"
    }
    IpPermission5 = @{
        CidrIp = "10.0.0.0/16"
        IpProtocol = "-1"
        FromPort = 0
        ToPort = 0
        Description = "all: vpc"
    }
}

If( -not (Get-EC2SecurityGroup -Filter $SgTagFilter))
{
    $SgParams = @{
        VpcId = $TargetVpcId
        GroupName = $SgName
        GroupDescription = $SgName
        TagSpecification = $SgTag
    }
    $TargetSgId = New-EC2SecurityGroup @SgParams

    $IpPermissions = @()
    ForEach($IpRangeObject In $IpRangeObjects.GetEnumerator())
    {
        $IpPermissionParams = @{
            CidrIp = $IpRangeObject.Value.CidrIp
            IpProtocol = $IpRangeObject.Value.IpProtocol
            FromPort = $IpRangeObject.Value.FromPort
            ToPort = $IpRangeObject.Value.ToPort
            Description = $IpRangeObject.Value.Description
        }
        $IpPermissions += New-EC2Ipv4Range @IpPermissionParams
    }

    Grant-EC2SecurityGroupIngress -GroupId $TargetSgId -IpPermissions $IpPermissions
}
Else
{
    throw "${SgName}: すでに存在する名前です。"
}

# ------------------------------------
#  IAM ロールの作成
# ------------------------------------

$RoleName = "TEST-Role"
$RoleTag = New-Object -TypeName Amazon.IdentityManagement.Model.Tag -Property @{ Key="Name"; Value=$RoleName }
$AssumeRolePolicyDocument = @'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
              "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
'@
$PolicyArn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"

$RoleCheck = Get-IAMRoleList | Where-Object -FilterScript { $_.RoleName -eq $RoleName }

If( -not $RoleCheck)
{
    $RoleParams = @{
        AssumeRolePolicyDocument = $AssumeRolePolicyDocument
        RoleName = $RoleName
        Description = $RoleName
        Tag = $RoleTag
    }
    New-IAMRole @RoleParams

    Register-IAMRolePolicy -PolicyArn $PolicyArn -RoleName $RoleName
}
Else
{
    throw "${RoleName}: すでに存在する名前です。"
}

$ProfCheck = Get-IAMInstanceProfileList | Where-Object -FilterScript { $_.InstanceProfileName -eq $TestRole }

If( -not $ProfCheck)
{
    New-IAMInstanceProfile -InstanceProfileName $RoleName
    Add-IAMRoleToInstanceProfile -InstanceProfileName $RoleName -RoleName $RoleName
}
Else
{
    throw "${RoleName}: すでに存在する名前です。"
}

# ------------------------------------
#  キーペアの作成
# ------------------------------------

$KeyName = "TEST-Key"
$KeyTag = New-EC2NameTag -ResourceType "key-pair" -TagValue $KeyName
$KeyPath = "C:\Work\Key\${KeyName}.pem"
$KeyCheck = Get-EC2KeyPair | Where-Object -FilterScript { $_.KeyName -eq $KeyName }

If( -not $KeyCheck)
{
    (New-EC2KeyPair -KeyName $KeyName -TagSpecification $KeyTag).KeyMaterial | 
    Out-File -FilePath $KeyPath -Encoding ascii
}
Else
{
    throw "${KeyName}: すでに存在する名前です。"
}

# ------------------------------------
#  インスタンス起動
# ------------------------------------

$InstanceName = "test-01"
$InstanceTag = New-EC2NameTag -ResourceType "instance" -TagValue $InstanceName
$EbsParams = @{
    VolumeSize = "8"
    VolumeType = "Gp2"
    DeleteOnTermination = $true
    DeviceName = "/dev/xvda"
}
$InstanceEbs = New-EC2BlockDevice @EbsParams

$ComposeUrl = "https://api.github.com/repos/docker/compose/releases/latest"
$ComposeVersion = ((Invoke-WebRequest -Method Get -Uri $ComposeUrl -UseBasicParsing).Content | ConvertFrom-Json).name

$UserData = @"
#!/bin/bash
timedatectl set-timezone Asia/Tokyo
localectl set-locale LANG=ja_JP.UTF8
localectl set-keymap jp106
localectl set-keymap jp-OADG109A
hostnamectl set-hostname ${InstanceName}
yum update -y
yum install -y docker git
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user
curl -L -v https://github.com/docker/compose/releases/download/${ComposeVersion}/docker-compose-`$(uname -s)-`$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
"@ -replace "`r`n", "`n"

$EC2Params = @{
    MinCount = 1
    MaxCount = 1
    InstanceType = [Amazon.EC2.InstanceType]::T3Nano
    CreditSpecification_CpuCredit = "standard"
    PrivateIpAddress = "10.0.0.10"
    AssociatePublicIp = $true
    KeyName = $KeyName
    ImageId = $TargetAmiId
    SubnetId = $TargetSubnetId 
    SecurityGroupId = $TargetSgId
    BlockDeviceMapping = $InstanceEbs
    EbsOptimized = $false
    DisableApiTermination = $false
    #IamInstanceProfile_Name = $RoleName
    TagSpecification = $InstanceTag
    EncodeUserData = $true
    UserData = $UserData
}

$Reservation = New-EC2Instance @EC2Params
$Instances = $Reservation.Instances

While((Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $Instances.InstanceId).InstanceState.Name.Value -ne "running")
{
    $LogTime = ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
    Write-Host "[${LogTime}] Waiting for the instances to launch..."
    Start-Sleep -Seconds 15
}

Start-Sleep -Seconds 180

$Instances | ForEach-Object -Process {
    $ElasticIp = (New-EC2Address -Domain vpc).AllocationId
    Register-EC2Address -InstanceId $_.InstanceId -AllocationId $ElasticIp
    Register-EC2IamInstanceProfile -InstanceId $_.InstanceId -IamInstanceProfile_Name $RoleName
}
