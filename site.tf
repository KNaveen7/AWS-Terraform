variable "AWS_ACCESS_KEY" {}
variable "AWS_SECRET_KEY" {}
variable "S3_Bucket" {}
 
provider "aws" {
        access_key = "${var.AWS_ACCESS_KEY}"
        secret_key = "${var.AWS_SECRET_KEY}"
        region = "ap-southeast-1"
}
 
#Creation of S3 bucket
 
resource "aws_iam_user" "prod_user" {
    name = "TerrformUser"
}
 
resource "aws_iam_access_key" "prod_user" {
    user = "${aws_iam_user.prod_user.name}"
}
 
resource "aws_iam_user_policy" "prod_user_ro" {
    name = "prod"
    user = "${aws_iam_user.prod_user.name}"
   policy= <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${var.S3_Bucket}",
                "arn:aws:s3:::${var.S3_Bucket}/*"
            ]
        }
   ]
}
EOF
}
 
resource "aws_s3_bucket" "prod_bucket" {
    bucket = "${var.S3_Bucket}"
    acl = "public-read"
 
    cors_rule {
        allowed_headers = ["*"]
        allowed_methods = ["PUT","POST"]
        allowed_origins = ["*"]
        expose_headers = ["ETag"]
        max_age_seconds = 3000
    }
 
    policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "PublicReadForGetBucketObjects",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${var.S3_Bucket}/*"
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_iam_user.prod_user.arn}"
            },
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${var.S3_Bucket}",
                "arn:aws:s3:::${var.S3_Bucket}/*"
            ]
        }
    ]
}
EOF
}
 
resource "aws_launch_configuration" "agent-lc" {
    name_prefix = "agent-lc-"
    image_id = "ami-a59b49c6"
    instance_type = "t2.micro"
 
    lifecycle {
        create_before_destroy = true
    }
 
    root_block_device {
        volume_type = "gp2"
        volume_size = "50"
    }
}
 
resource "aws_autoscaling_group" "agents" {
    availability_zones = ["ap-southeast-1a"]
    name = "agents"
    max_size = "10"
    min_size = "1"
    health_check_grace_period = 500
    health_check_type = "EC2"
    desired_capacity = 2
    force_delete = true
    launch_configuration = "${aws_launch_configuration.agent-lc.name}"
 
    tag {
        key = "Name"
        value = "Agent Instance"
        propagate_at_launch = true
    }
}
 
resource "aws_autoscaling_policy" "agents-scale-up" {
    name = "agents-scale-up"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.agents.name}"
}
 
resource "aws_autoscaling_policy" "agents-scale-down" {
    name = "agents-scale-down"
    scaling_adjustment = -1
    adjustment_type = "ChangeInCapacity"
    cooldown = 200
    autoscaling_group_name = "${aws_autoscaling_group.agents.name}"
}
 
resource "aws_cloudwatch_metric_alarm" "memory-high" {
    alarm_name = "mem-util-high-agents"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "MemoryUtilization"
    namespace = "System/Linux"
    period = "300"
    statistic = "Average"
    threshold = "80"
    alarm_description = "Monitors the ec2 memory for high utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.agents-scale-up.arn}"
    ]
    dimensions {
        AutoScalingGroupName = "${aws_autoscaling_group.agents.name}"
    }
}
 
resource "aws_instance" "web" {
     ami = "ami-a59b49c6"
     instance_type = "t2.micro"
 
provisioner "local-exec" {
        command = "curl http://169.254.169.254/latest/meta-data/hostname > /home/ec2-user/Files_Test/Userdata_File.txt"
    }
}
 
 
resource "aws_s3_bucket" "index" {
  bucket = "testname"
  key = "Userdata_File.txt"
#Source path of the file
  source = "/home/ec2-user/Files_Test/Userdata_File.txt"
  content_type = "text/html"
  etag = "/home/ec2-user/Files_Test/Userdata_File.txt"
}