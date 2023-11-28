#!/bin/bash

# Create log file
runDate=$(date +"%Y%m%d-%H%M")
logFile=~/$0-$runDate
echo "Script Starting @ $runDate" > $logFile

# Create VPC
VPC=$(aws ec2 create-vpc --cidr-block 172.16.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Task2VPC}]' --query Vpc.VpcId --output text)

# Create subnets in the new VPC
subnet0=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.0.0/24 --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Subnet0 Public}]' --availability-zone us-east-1a --query Subnet.SubnetId --output text)
subnet1=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.1.0/24 --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Subnet1 Public}]' --availability-zone us-east-1a --query Subnet.SubnetId --output text)

# Determine the route table id for the VPC
PubRouteTable=$(aws ec2 describe-route-tables --query "RouteTables[?VpcId == '$VPC'].RouteTableId" --output text)

# Update tag
aws ec2 create-tags --resources $PubRouteTable --tags 'Key=Name,Value=Public route Table'

# Create private route table
PrivRouteTable=$(aws ec2 create-route-table --vpc-id "$VPC" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Private Route Table}]' --query RouteTable.RouteTableId --output text)

# Create Internet Gateway
internetGateway=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)

# Attach gateway to VPC
aws ec2 attach-internet-gateway --vpc-id "$VPC" --internet-gateway-id "$internetGateway"

# Create default route to Internet Gateway
aws ec2 create-route --route-table-id "$PubRouteTable" --destination-cidr-block 0.0.0.0/0 --gateway-id "$internetGateway" --query 'Return' --output text

# Apply Public route table to subnet0
aws ec2 associate-route-table --subnet-id "$subnet0" --route-table-id "$PubRouteTable" --query 'AssociationState.State' --output text

# Apply Private route table to subnet1
aws ec2 associate-route-table --subnet-id "$subnet1" --route-table-id "$PrivRouteTable" --query 'AssociationState.State' --output text

# Obtain public IP address on launch
aws ec2 modify-subnet-attribute --subnet-id "$subnet0" --map-public-ip-on-launch

# Create.ssh folder if it doesn't exist
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

# Allow SSH and http traffic
aws ec2 authorize-security-group-ingress --group-id "$webAppSG" --protocol tcp --port 22 --cidr 0.0.0.0/0 --query 'Return' --output text
aws ec2 authorize-security-group-ingress --group-id "$webAppSG" --protocol tcp --port 80 --cidr 0.0.0.0/0 --query 'Return' --output text

# Create EC2 Instance in public subnet - Uses golden image created in task 1
pubEC2ID=$(aws ec2 run-instances --image-id ami-08a85687358dd743b --count 1 --instance-type t2.micro --key-name CSE3SOX-A2-key-pair --security-group-ids "$webAppSG" --subnet-id "$subnet0" --query Instances[].InstanceId --output text)

# Create EC2 Instance in private subnet - Uses golden image created in task 1
privEC2ID=$(aws ec2 run-instances --image-id ami-08a85687358dd743b --count 1 --instance-type t2.micro --key-name CSE3SOX-A2-key-pair  --subnet-id "$subnet1" --query Instances[].InstanceId --output text)

# Determine public IP address of EC2 instance
publicIP=$(aws ec2 describe-instances --instance-ids "$pubEC2ID" --query Reservations[].Instances[].PublicIpAddress  --output text)

# Determine private IP address of EC2 instance
privateIP=$(aws ec2 describe-instances --instance-ids "$privEC2ID" --query Reservations[].Instances[].PublicIpAddress  --output text)

# Script complete message
greenText='\033[0;32m'
NC='\033[0m' # No Color
echo "Connect to pubilc EC2 instance using the command below"
echo -e "\n${greenText}\t\t ssh -i ~/.ssh/CSE3SOX-A2-key-pair.pem ec2-user@$publicIP ${NC}\n"
echo "Connect to private EC2 instance using the command below"
echo -e "\n${greenText}\t\t ssh -i ~/.ssh/CSE3SOX-A2-key-pair.pem ec2-user@$privateIP ${NC}\n"
