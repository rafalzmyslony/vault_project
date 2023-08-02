resource "aws_instance" "todo_app_server" {
    instance_type = "t2.micro"
    depends_on = [aws_subnet.private, aws_instance.database_ec2]
    ami = "ami-04e601abe3e1a910f"
    key_name      = aws_key_pair.generated_key.key_name
    vpc_security_group_ids = [
        aws_security_group.todo_app.id
    ]
    subnet_id = aws_subnet.public_app.id
    associate_public_ip_address = true
    tags = {
        Name = "todo_app_server"
    }
    root_block_device  {
      volume_size = 15
      volume_type = "gp2"
    }

    user_data = <<EOF
#!/bin/bash
cat > /home/ubuntu/ip_database << EOL
${aws_instance.database_ec2.private_ip}
EOL

apt-get -y update
apt -y install net-tools
apt -y install python3-pip
apt -y install python3.10-venv
apt-get -y update
apt-get -y install libpq-dev libpq-dev python3-dev
apt-get -y install postgresql
apt-get -y install gcc


apt -y update
apt -y install build-essential
wget https://go.dev/dl/go1.20.5.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.20.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
export GOPATH=/usr/local/go/bin
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
apt -y update
apt -y install vault
cd /home/ubuntu && git clone https://github.com/rafalzmyslony/vault_project-todo_app
python3 -m venv /home/ubuntu/app
mv /home/ubuntu/Todo-App/* /home/ubuntu/app
chown -R ubuntu:ubuntu app/
echo "source ~/app/bin/activate " | sudo tee -a /home/ubuntu/.bashrc >/dev/null
/home/ubuntu/app/bin/pip install -r /home/ubuntu/app/requirements.txt
cat >> /home/ubuntu/.bashrc << EOL
export DB_HOST=${aws_instance.database_ec2.private_ip}
export DB_PORT=5432
export DB_NAME=${var.db_name}
export DB_USER=${var.db_role_name}
export DB_PASSWORD=${var.db_pass}
EOL

cat >> /etc/systemd/system/todo_app.service << EOL
[Unit]
Description=Todo app
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
EnvironmentFile=/home/ubuntu/app/todo_env
RuntimeDirectory=app
WorkingDirectory=/home/ubuntu/app
ExecStart=/home/ubuntu/app/bin/uwsgi /home/ubuntu/app/uwsgi.ini
KillMode=mixed
Restart=on-failure

[Install]
WantedBy=multi-user.target                               
EOL

cat >> /home/ubuntu/app/todo_env << EOL
DB_HOST=${aws_instance.database_ec2.private_ip}
DB_PORT=5432
DB_NAME=${var.db_name}
DB_USER=${var.db_role_name}
DB_PASSWORD=${var.db_pass}
EOL
chown ubuntu:ubuntu /home/ubuntu/app/todo_env
chmod 770 /home/ubuntu/app/todo_env
cd /etc/systemd/system/
systemctl start todo_app.service
systemctl enable todo_app.service
todo_app.service restart  
EOF
# *1*
    iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
}
resource "aws_instance" "vault_server" {
    instance_type = "t2.micro"
    #depends_on = [aws_subnet.private, aws_instance.db_todo]
    ami = "ami-04e601abe3e1a910f"
    key_name      = aws_key_pair.generated_key.key_name
    vpc_security_group_ids = [
        aws_security_group.vault.id
    ]
    subnet_id = aws_subnet.public_vault.id
    associate_public_ip_address = true
    tags = {
        Name = "vault server"
    }
    root_block_device  {
      volume_size = 8
      volume_type = "gp2"
    }
    user_data = <<EOF1
#!/bin/bash
apt-get -y update
apt -y install net-tools
apt -y install python3-pip
apt -y install python3.10-venv


apt -y update
apt -y install build-essential
wget https://go.dev/dl/go1.20.5.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.20.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
export GOPATH=/usr/local/go/bin
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
apt -y update
apt -y install vault
pip3 install hvac -y

cat >> /home/ubuntu/.bashrc <<-EOF2
export TMP_VAULT_ACCESS_KEY=${aws_iam_access_key.user_iam_key.id}
export TMP_VAULT_SECRET_KEY=${aws_iam_access_key.user_iam_key.secret}
export VAULT_ADDR='http://0.0.0.0:8200'
EOF2

cat >> /home/ubuntu/vault_load_pass <<-EOF3
vault secrets enable -version=1 kv
vault kv put kv/data/db/todo_app password="pass_to_db"  # password to todo-app database (then log to db and change password)
vault policy write vault-policy-for-aws-ec2role - <<-EOF4
# Grant 'read' permission to paths prefixed by 'kv/data/db/todo_app''
path "kv/data/db/todo_app" {
  capabilities = [ "read" ]
}
EOF4
vault auth enable aws
vault write auth/aws/config/client secret_key=\$TMP_VAULT_SECRET_KEY access_key=\$TMP_VAULT_ACCESS_KEY
vault write auth/aws/role/vault-role-for-aws-ec2role \\
    auth_type=iam \\
bound_iam_principal_arn=arn:aws:iam::${var.aws_account_id}:role/aws-ec2role-for-vault-authmethod \\
    policies=vault-policy-for-aws-ec2role

EOF3
vault server -dev -dev-root-token-id="root" -dev-listen-address=0.0.0.0:8200
EOF1
}
resource "aws_instance" "database_ec2" {
    instance_type = "t2.micro"
    depends_on = [aws_nat_gateway.db_nat_gateway]
    ami = "ami-04e601abe3e1a910f"
    key_name      = aws_key_pair.generated_key.key_name
    vpc_security_group_ids = [
        aws_security_group.database.id
    ]
    associate_public_ip_address = false
    subnet_id = aws_subnet.private.id
    tags = {
        Name = "database"
    }
    root_block_device  {
      volume_size = 8
      volume_type = "gp2"
    }
    user_data = <<EOF
#!/bin/bash
cat > /home/ubuntu/ip_address.txt << EOL
IP address of second EC2 instance 
EOL
apt-get -y update
apt -y install net-tools
apt -y install python3-pip
apt -y install python3.10-venv
apt-get -y update
apt-get -y install libpq-dev libpq-dev python3-dev
pip install psycopg2
apt install python3-psycopg2

apt -y update
apt -y install build-essential
apt -y install wget sudo curl gnupg -y
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt -y update
apt -y install postgresql-15


# Install PostgreSQL
apt-get update
apt-get install -y postgresql
useradd -m -s /sbin/nologin ${var.db_role_name}
sudo -u postgres createdb ${var.db_name}
sudo -u postgres psql -c "CREATE ROLE \"${var.db_role_name}\" LOGIN PASSWORD '${var.db_pass}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"${var.db_name}\" TO ${var.db_role_name};"
sudo -u postgres psql -c "ALTER DATABASE \"${var.db_name}\" OWNER TO \"${var.db_role_name}\";"
systemctl restart postgresql

EOF
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "local_file" "ssh_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/todo-private.key"
  file_permission = 0400
}
resource "aws_key_pair" "generated_key" {
  key_name   = "todoapp"
  public_key = tls_private_key.ssh_key.public_key_openssh
}