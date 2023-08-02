#==============VPC and network==============
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  
}
# subnet private - hosts in this subnet have access to internet gateway
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "private subnet"
  }
}
resource "aws_subnet" "public_app" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "public subnet"
  }
}

resource "aws_subnet" "public_vault" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"

  tags = {
    Name = "public subnet for vault"
  }
}
resource "aws_internet_gateway" "project1_igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "igw_for_vpc"

  }
}
#=================Routing=============

# routing table that makes: "0.0.0.0/0" goes to internet gateway
# no local reference because it is implicitly created, like local 10.0.0.0/16
resource "aws_route_table" "project1_public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.project1_igw.id
  }
}
# assign route table for subnet --> association
resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.project1_public_rt.id
  subnet_id = aws_subnet.public_app.id
}
# creates local routing within VPC for hosts in private subnet
# associate nat gateway with 0.0.0.0 --> 
resource "aws_route_table" "project1_private_rt" {
  vpc_id = aws_vpc.main.id
  route {
  cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.db_nat_gateway.id
  }
}
resource "aws_route_table_association" "private" {
  route_table_id = aws_route_table.project1_private_rt.id
  subnet_id = aws_subnet.private.id
}
#routing table also for vault public subnet
# assign route table for subnet --> association
resource "aws_route_table_association" "public_vault" {
  route_table_id = aws_route_table.project1_public_rt.id
  subnet_id = aws_subnet.public_vault.id
}

#================nat gateway=================
#.1 AWS EIP elastic IP address
resource "aws_eip" "nat_eip" {
 
}
#. create NAT gw, and assign elastic IP, you must attach to public subnet!
resource "aws_nat_gateway" "db_nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_app.id
  connectivity_type = "public"


  tags = {
    Name = "private subnet NAT"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.project1_igw]
}
#============== Security Groups==========================
# 1. todo app
resource "aws_security_group" "todo_app" {
  depends_on = [aws_vpc.main]
  vpc_id = "${aws_vpc.main.id}"
  name_prefix = "todo_app"
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    #port 8080 for todo app
    ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]

  }

}

# 2. vault
resource "aws_security_group" "vault" {
  depends_on = [aws_vpc.main]
  vpc_id = "${aws_vpc.main.id}"
  name_prefix = "vault"
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 8200
    to_port = 8200
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]

  }

}

# 3. db
resource "aws_security_group" "database" {
  depends_on = [aws_vpc.main]
  vpc_id = "${aws_vpc.main.id}"
  name_prefix = "database"
  /*
# allow ingress everything from EC2 which is under security group called todo_app
# this causes error, I must do it via separate resource gr..security_rule
  ingress {
    security_groups = ["${aws_security_group.todo_app.id}"]
  }
*/
# special rule with allow all traffic to go out

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]

  }
}


resource "aws_security_group_rule" "allow_all" {
  type              = "ingress"
  to_port           = 0
  protocol          = "-1"
  source_security_group_id = aws_security_group.todo_app.id
  from_port         = 0
  security_group_id = "${aws_security_group.database.id}"
}

#=============IAM section===================
resource "aws_iam_user" "user_iam" {
  name = "aws-iamuser-for-vault-authmethod"

  tags = {
    user = "vault"
  }
}
resource "aws_iam_access_key" "user_iam_key" {
  user    = aws_iam_user.user_iam.name
}
resource "aws_iam_policy" "policy_vault" {
  name        = "aws-iampolicy-for-vault-authmethod"
  description = "My test policy"

  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:DescribeInstances",
        "iam:GetInstanceProfile",
        "iam:GetUser",
        "iam:ListRoles",
        "iam:GetRole"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]

}
EOT
}
resource "aws_iam_user_policy_attachment" "attachment" {
  user       = aws_iam_user.user_iam.name
  policy_arn = aws_iam_policy.policy_vault.arn
}

resource "aws_iam_role" "ec2_role" {
  name = "aws-ec2role-for-vault-authmethod"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
  })

  tags = {
    dest = "role_for_ec2_client_Vault"
  }
}
#*1*
# profile, role can be assigned to many profiles, but one profile to one ec2
# this profile will be attach to ec2 in aws_instance
# in gui, we attach role to ec2, but internally it created profile with iam role
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}