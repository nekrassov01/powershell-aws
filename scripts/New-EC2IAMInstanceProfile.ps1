Set-DefaultAWSRegion -Region "ap-northeast-1" -Scope Script
Import-Module -Name AWS.Tools.IdentityManagement
$iamPolicies = @()

$awsAccountId = "000000000000"
$bucketName = "docker-django-blog"

# Create S3 IAM Policy
$policyName = "_s3_${bucketName}_write"
$policyDocument = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::${bucketName}"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::${bucketName}/*"
        },
        {
            "Sid": "VisualEditor2",
            "Effect": "Allow",
            "Action": "s3:ListAllMyBuckets",
            "Resource": "*"
        }
    ]
}
"@

$param = @{
    PolicyName = $policyName
    Description = $policyName
    PolicyDocument = $policyDocument
}

$s3Policy = New-IAMPolicy @param
$iamPolicies += $s3Policy

# Create SSM ParameterStore IAM Policy
$policyName = "_ssm_parameter-store_write"
$policyDocument = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "ssm:PutParameter",
                "ssm:DeleteParameter",
                "ssm:GetParameterHistory",
                "ssm:GetParametersByPath",
                "ssm:GetParameters",
                "ssm:GetParameter",
                "ssm:DeleteParameters"
            ],
            "Resource": "arn:aws:ssm:ap-northeast-1:${awsAccountId}:parameter/*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "ssm:DescribeParameters",
            "Resource": "*"
        }
    ]
}
"@

$param = @{
    PolicyName = $policyName
    Description = $policyName
    PolicyDocument = $policyDocument
}

$ssmPolicy = New-IAMPolicy @param
$iamPolicies += $ssmPolicy

# Create IAM Role
$roleName = "_ec2_role"
$roleTag = New-Object -TypeName Amazon.IdentityManagement.Model.Tag -Property @{ Key="Name"; Value=$roleName }
$assumeRolePolicyDocument = @'
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

$param = @{
    AssumeRolePolicyDocument = $assumeRolePolicyDocument
    RoleName = $roleName
    Description = $roleName
    Tag = $roleTag
}

New-IAMRole @param

# Register IAM Policy to IAM Role
$iamPolicies | ForEach-Object -Process { Register-IAMRolePolicy -PolicyArn $_.Arn -RoleName $roleName }

# Create IAM Instance Profile, Add IAM Role to IAM Instance Profile
New-IAMInstanceProfile -InstanceProfileName $roleName
Add-IAMRoleToInstanceProfile -InstanceProfileName $roleName -RoleName $roleName

# Cleanup Variables
Get-Variable | Remove-Variable -ErrorAction Ignore