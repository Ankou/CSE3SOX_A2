#!/bin/bash
# Create log file
runDate=$(date +"%Y%m%d-%H%M")
logFile=~/$0-$runDate
echo "Script Starting @ $runDate" > $logFile

# Create VPC
VPC=$(aws ec2 create-vpc --cidr-block 172.16.0.0/16 --query Vpc.VpcId --output text)

# Create subnets in the new VPC
subnet0=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.0.0/24 --query Subnet.SubnetId --output text)
subnet1=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.1.0/24 --query Subnet.SubnetId --output text)
subnet2=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.2.0/24 --query Subnet.SubnetId --output text)

# Create Internet Gateway
internetGateway=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)

# Attach gateway to VPC
echo "Attach gateway to VPC"
aws ec2 attach-internet-gateway --vpc-id "$VPC" --internet-gateway-id "$internetGateway"

# Create route table
routeTable=$(aws ec2 create-route-table --vpc-id "$VPC" --query RouteTable.RouteTableId --output text)

# Create default route to Internet Gateway
echo "Create default route to igw"
aws ec2 create-route --route-table-id "$routeTable" --destination-cidr-block 0.0.0.0/0 --gateway-id "$internetGateway"

# Apply route table to subnet0
echo "Apply route table to subnet0"
aws ec2 associate-route-table --subnet-id "$subnet0" --route-table-id "$routeTable"

# Obtain public IP address on launch
aws ec2 modify-subnet-attribute --subnet-id "$subnet0" --map-public-ip-on-launch

# Create.ssh folder
if [ ! -d ~/.ssh/ ]; then
        mkdir ~/.ssh/
        echo "Creating directory"
fi

# Generate Key Pair
aws ec2 create-key-pair --key-name CSE3SOX-A2-key-pair --query 'KeyMaterial' --output text > ~/.ssh/CSE3SOX-A2-key-pair.pem

# Change permissions of Key Pair
chmod 400 ~/.ssh/CSE3SOX-A2-key-pair.pem

# Create Security Group
webAppSG=$(aws ec2 create-security-group --group-name webApp-sg --description "Security group for A2 Web Application" --vpc-id "$VPC" --query 'GroupId' --output text)

# Allow SSH
aws ec2 authorize-security-group-ingress --group-id "$webAppSG" --protocol tcp --port 22 --cidr 0.0.0.0/0 --query 'Return' --output text

# Create EC2 Instance
ec2ID=$(aws ec2 run-instances --image-id ami-0b0dcb5067f052a63 --count 1 --instance-type t2.micro --key-name CSE3SOX-A2-key-pair --security-group-ids "$webAppSG" --subnet-id "$subnet0" --user-data file://user_data.txt --query Instances[].InstanceId --output text)

# Determine public IP address of EC2 instance
publicIP=$(aws ec2 describe-instances --instance-ids "$ec2ID" --query Reservations[].Instances[].PublicIpAddress  --output text)

echo "VPC is $VPC"
echo "Subnet0 is $subnet0"
echo "Public IP address is $publicIP"

echo "Connect using the command below"
echo -e "\t\t ssh -i .ssh/CSE3SOX-A2-key-pair.pem ec2-user@$publicIP"
#