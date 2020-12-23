Set-DefaultAWSRegion -Region "ap-northeast-1" -Scope Script
Import-Module -Name AWS.Tools.EC2 -Force

$instanceName = "web-01"

# Difine Name Tag
$tag = @{ Key="Name"; Value=$instanceName }
$nameTagObj = New-Object -TypeName Amazon.EC2.Model.TagSpecification
$nameTagObj.ResourceType = "instance"
$nameTagObj.Tags.Add($tag)

# Define EBS Setting
$bd = New-Object -TypeName Amazon.EC2.Model.EbsBlockDevice
$bd.VolumeSize = 50
$bd.VolumeType = "gp3"
$bd.Iops = 3000
$bd.DeleteOnTermination = $true
$bdm = New-Object -TypeName Amazon.EC2.Model.BlockDeviceMapping
$bdm.DeviceName = "/dev/xvda"
$bdm.Ebs = $bd

# Define UserData Shell Script
$userData = @"
#!/bin/bash
timedatectl set-timezone Asia/Tokyo
localectl set-locale LANG=ja_JP.UTF8
localectl set-keymap jp106
localectl set-keymap jp-OADG109A
hostnamectl set-hostname ${instanceName}

aws configure set region ap-northeast-1
aws configure set output json

yum update -y
yum install -y docker git jq

ec2_username=`$(aws ssm get-parameters-by-path --path "/account/ec2" --with-decryption --region ap-northeast-1 | jq -r '.Parameters[1].Value')
ec2_password=`$(aws ssm get-parameters-by-path --path "/account/ec2" --with-decryption --region ap-northeast-1 | jq -r '.Parameters[0].Value')
ec2_publickey=`$(aws ssm get-parameters-by-path --path "/account/ec2/key" --with-decryption --region ap-northeast-1 | jq -r '.Parameters[0].Value')
git_username=`$(aws ssm get-parameters-by-path --path "/account/git" --with-decryption --region ap-northeast-1 | jq -r '.Parameters[1].Value')
git_password=`$(aws ssm get-parameters-by-path --path "/account/git" --with-decryption --region ap-northeast-1 | jq -r '.Parameters[0].Value')

useradd `$ec2_username
usermod -G wheel `$ec2_username
echo `$ec2_password | sudo passwd --stdin `$ec2_username
touch /etc/sudoers.d/`${ec2_username}
echo "`${ec2_username} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/`${ec2_username}
sed -i -e 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
systemctl restart sshd

ssh_dir=/home/`${ec2_username}/.ssh
key_file=`${ssh_dir}/authorized_keys

mkdir -p `$ssh_dir
touch `$key_file
echo `$ec2_publickey >> `$key_file

chown `$ec2_username:`$ec2_username `$key_file
chmod 600 `$key_file

chown `${ec2_username}:`${ec2_username} `$ssh_dir
chmod 700 `$ssh_dir

systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user
usermod -a -G docker `$ec2_username

compose_dir=/opt/docker-compose
compose_version=`$(curl https://api.github.com/repos/docker/compose/releases/latest | jq .name -r)
mkdir -p `$compose_dir
git clone -b `${compose_version} "https://`${git_username}:`${git_password}@github.com/docker/compose.git" `$compose_dir
cd `$compose_dir
./script/build/linux
cp dist/docker-compose-Linux-aarch64 /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
"@ -replace "`r`n", "`n"

# Define EC2 Instance Parameters
$params = @{
    MinCount = 1
    MaxCount = 1
    InstanceType = [Amazon.EC2.InstanceType]::T4gMicro
    CreditSpecification_CpuCredit = "standard"
    PrivateIpAddress = "10.0.0.10"
    AssociatePublicIp = $true
    KeyName = "AWS-Key"
    ImageId = "ami-077527e5c50f1d6d1"
    SubnetId = "subnet-00000000000000000"
    SecurityGroupId = "sg-11111111111111111", "sg-2222222222222222"
    BlockDeviceMapping = $bdm
    EbsOptimized = $true
    DisableApiTermination = $false
    IamInstanceProfile_Name = "_ssm_role"
    TagSpecification = $nameTagObj
    EncodeUserData = $true
    UserData = $userData
}

# Run EC2 Instance
$reservation = New-EC2Instance @params
$instances = $reservation.Instances

# Wait for EC2 Instance Launch
while ((Get-EC2InstanceStatus -IncludeAllInstance $true -InstanceId $instances.InstanceId).InstanceState.Name.Value -ne "running")
{
    $logTime = ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
    Write-Host "[${logTime}] Waiting for the instances to launch..."
    Start-Sleep -Seconds 15
}

Start-Sleep -Seconds 180

# Attach Elastic IP to EC2 Instance
$instances | ForEach-Object -Process {
    $elasticIp = (New-EC2Address -Domain vpc).AllocationId
    Register-EC2Address -InstanceId $_.InstanceId -AllocationId $elasticIp
}

# Cleanup Variables
Get-Variable | Remove-Variable -ErrorAction Ignore