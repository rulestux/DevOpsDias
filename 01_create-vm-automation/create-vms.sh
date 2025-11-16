#!/usr/bin/env bash

# definindo variável para chave ssh:
KEY_NAME="devops-keypair"
# definindo variável para Security Group:
SG_NAME="devops-sg-ie"

# variáveis para os dados de recursos de instâncias AWS, a saber:
# VPC, SUBNET_ID e AMI (sistema);
# os dados são obtidos com 'queries' e atribuídos às variáveis através de
# estruturas de inversão de comando:
VPC_ID=$(aws ec2 describe-vpcs \
    --filters Name=isDefault,Values=true \
    --query "Vpcs[0].VpcId" \
    --output text)

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters Name=default-for-az,Values=true \
    --query "Subnets[0].SubnetId" \
    --output text)

# obtendo AMI através de filtro que lista as imagens públicas da AWS com o
# padrão de nomes 'amzn2' (Amazon Lunux 2), ordena pelas versões mais recentes
# e retorna o respectivo ID da mais recente:
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

# verificar key-pair 'KEY_NAME' na AWS:
aws ec2 describe-key-pairs --key-names "$KEY_NAME" > /dev/null 2>&1

# testar se ela existe, com a saída do comando acima:
if [ $? -ne 0 ]; then
    # criar, caso retorne erro (caso não exista):
    echo "Keypair not found. Creating keypair $KEY_NAME..."
    aws ec2 create-key-pair --key-name "$KEY_NAME" \
        --query 'KeyMaterial' --output text > "$KEY_NAME.pem"
    chmod 400 "$KEY_NAME.pem"
# pular criação de keypair, caso exista:
else
    echo "Kaypair $KEY_NAME already exists on AWS. Skipping creating."
    # testando se não existe o arquivo local '*.pem' para notificar:
    if [ ! -f "$KEY_NAME.pem" ]; then
        echo "Local file $KEY_NAME.pem does not exist. Create manually or download the original one."
        # output error:
        exit 1
    fi
fi

# criar Security Group, guardando o respectivo ID na variável SG_ID:
SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "via loop access" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

# habilitar porta 22 para acesso do Security Group:
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# criar lista com o nome das Virtual Machines a serem criadas:
VMS=(vm01 vm02 vm03)

# estrutura 'for' para criar um loop que percorrerá a lista 'VMS', a fim de
# criar uma VM para cada item da lista:
for NAME in "${VMS[@]}"; do
    echo "Creating instance: $NAME..."

    # criando instância tipo 't2.micro':
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --count 1 \
        --instance-type t2.micro \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "Instance $NAME created with ID: $INSTANCE_ID"

    # aguardando disponibilidade:
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    echo "Instance $NAME is now running."
done
