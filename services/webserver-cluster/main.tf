data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    # Replace this with your bucket name!
    bucket = "jc-testing-terraform-up-and-running-state"
    key    = "stage/data-stores/mysql/terraform.tfstate"
    region = "ap-southeast-2"
  }
}

terraform {
  backend "s3" {
    # Replace this with your bucket name!
    bucket         = "jc-testing-terraform-up-and-running-state"
    key            = "stage/services/webserver-cluster/terraform.tfstate"
    region         = "ap-southeast-2"
    # Replace this with your DynamoDB table name!
    dynamodb_table = "jc-testing-terraform-up-and-running-locks"
    encrypt        = true
  }
}

data "aws_availability_zones" "all" {}

resource "aws_launch_configuration" "example" {
  image_id        = "ami-0d767dd04ac152743"
  instance_type   = var.instance_type
  security_groups = [aws_security_group.instance.id]
  user_data = <<-EOF
                #!/bin/bash
                db_address="${data.terraform_remote_state.db.outputs.address}"
                db_port="${data.terraform_remote_state.db.outputs.port}"
                echo "Hello, World. DB is at $db_address:$db_port" >> index.html
                nohup busybox httpd -f -p "${var.server_port}" &
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.id
  availability_zones   = data.aws_availability_zones.all.names
  min_size = var.min_size
  max_size = var.max_size
  desired_capacity = 3
  
  load_balancers    = [aws_elb.example.name]
  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = var.cluster_name
    propagate_at_launch = true
  }
}

resource "aws_security_group" "instance" {
  name = "${var.cluster_name}-instance"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "example" {
  name               = var.cluster_name
  security_groups    = [aws_security_group.elb.id]
  availability_zones = data.aws_availability_zones.all.names

  health_check {
    target              = "HTTP:${var.server_port}/"
    interval            = 30
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  # This adds a listener for incoming HTTP requests.
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = var.server_port
    instance_protocol = "http"
  }
}

resource "aws_security_group" "elb" {
  name = "${var.cluster_name}-elb"
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Inbound HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}