resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab_key" {
  key_name   = "lab-vpc-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "local_file" "pem_file" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/lab-vpc-key.pem"
  file_permission = "0400"
}

resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Permite HTTP publico y SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP publico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH para pruebas"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

resource "aws_security_group" "backend_sg" {
  name        = "backend-sg"
  description = "Acepta solo trafico interno desde EC2 Web"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP 8080 solo desde Web"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  ingress {
    description     = "SSH solo desde Web"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-sg"
  }
}

resource "aws_instance" "backend" {
  ami                    = "ami-01e4a7224fcbfe81f"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.backend_sg.id]
  key_name               = aws_key_pair.lab_key.key_name

  user_data = <<-EOF
              #!/bin/bash
              mkdir -p /opt/backend
              echo '{"status": "ok", "service": "EC2 Backend Privado", "port": 8080}' > /opt/backend/index.html
              cd /opt/backend
              nohup python3 -m http.server 8080 --bind 0.0.0.0 > /var/log/backend.log 2>&1 &
              EOF

  tags = {
    Name = "EC2-Backend"
  }
}

resource "aws_instance" "web" {
  ami                    = "ami-01e4a7224fcbfe81f"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.lab_key.key_name

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y nginx
              cat << 'NGINXCONF' > /etc/nginx/conf.d/app.conf
              server {
                  listen 80 default_server;
                  server_name _;

                  location / {
                      root /usr/share/nginx/html;
                      index index.html;
                  }

                  location /api/ {
                      proxy_pass http://${aws_instance.backend.private_ip}:8080/;
                  }
              }
              NGINXCONF
              echo "<h1>EC2 Web Publico - Nginx OK</h1><p>Prueba el backend interno en <a href='/api/'>/api/</a></p>" > /usr/share/nginx/html/index.html
              systemctl enable nginx
              systemctl restart nginx
              EOF

  tags = {
    Name = "EC2-Web"
  }
}

output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}

output "backend_test_via_web_url" {
  value = "http://${aws_instance.web.public_ip}/api/"
}

output "backend_private_ip" {
  value = aws_instance.backend.private_ip
}
