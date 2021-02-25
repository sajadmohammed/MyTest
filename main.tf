provider "aws" {
  profile = "default"
  region  = "eu-west-1"
}

/*==== VPC ======*/
resource "aws_vpc" "my_vpc" {
  cidr_block       = "10.10.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "AND Digital VPC"
  }
}


/*==== Public Subnet West 1a ======*/
resource "aws_subnet" "public_eu_west_1a" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.10.10.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "Public Subnet eu-west-1a"
  }
}


/*==== Public Subnet West 1b ======*/
resource "aws_subnet" "public_eu_west_1b" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.10.11.0/24"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "Public Subnet eu-west-1b"
  }
}



/*==== Internet Gateway ======*/
resource "aws_internet_gateway" "my_vpc_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "My ANDDigital - Internet Gateway"
  }
}

/* Routing table for vpc subnets */
resource "aws_route_table" "my_vpc_public" {
    vpc_id = aws_vpc.my_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.my_vpc_igw.id
    }

    tags = {
        Name = "Public Subnets Route Table for My VPC"
    }
}


/*  associations Subnet with Default GW (IGW) */
resource "aws_route_table_association" "my_vpc_eu_west_1a_public" {
    subnet_id = aws_subnet.public_eu_west_1a.id
    route_table_id = aws_route_table.my_vpc_public.id
}


/*  associations Subnet with Default GW (IGW) */
resource "aws_route_table_association" "my_vpc_eu_west_1b_public" {
    subnet_id = aws_subnet.public_eu_west_1b.id
    route_table_id = aws_route_table.my_vpc_public.id
}


/* Security group - firewall */
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound connections"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow HTTP Security Group"
  }
}

  resource "aws_launch_configuration" "web" {
  name_prefix = "web-"

  image_id = "ami-0fc970315c2d38f01" 
  instance_type = "t2.micro"
  
  security_groups = [ aws_security_group.allow_http.id ]
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              sudo su
              yum update -y
              yum install -y httpd.x86_64
              systemctl start httpd.service
              systemctl enable httpd.service
              echo "Hello AND-Digital !!!  from $(hostname -f)" > /var/www/html/index.html
              EOF

  

  lifecycle {
    create_before_destroy = true
  }
}

/*   security Group for ELB */
resource "aws_security_group" "elb_http" {
  name        = "elb_http"
  description = "Allow HTTP traffic to instances through Elastic Load Balancer"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow HTTP through ELB Security Group"
  }
}
/*  associate Subnet and Security Group with ELB */
resource "aws_elb" "web_elb" {
  name = "web-elb"
  security_groups = [
    aws_security_group.elb_http.id
  ]
  subnets = [
    aws_subnet.public_eu_west_1a.id,
    aws_subnet.public_eu_west_1b.id
  ]

  cross_zone_load_balancing   = true

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }

}
/*  Set AutoScaling group  */
resource "aws_autoscaling_group" "web" {
  name = "${aws_launch_configuration.web.name}-asg"

  min_size             = 1
  desired_capacity     = 2
  max_size             = 6
  
  health_check_type    = "ELB"
  load_balancers = [
    aws_elb.web_elb.id
  ]

  launch_configuration = aws_launch_configuration.web.name

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity = "1Minute"

  vpc_zone_identifier  = [
    aws_subnet.public_eu_west_1a.id,
    aws_subnet.public_eu_west_1b.id
  ]

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }

}

output "elb_dns_name" {
  value = aws_elb.web_elb.dns_name
}