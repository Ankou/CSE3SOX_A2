#!/bin/bash

# Create VPC
VPC=$(aws ec2 create-vpc --cidr-block 172.16.0.0/16 --query Vpc.VpcId --output text)

# Create subnets in the new VPC
subnet0=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.0.0/24 --query Subnet.SubnetId --output text)
subnet1=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.1.0/24 --query Subnet.SubnetId --output text)
subnet2=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.2.0/24 --query Subnet.SubnetId --output text)

# Create Internet Gateway
internetGateway=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)

# Attach gateway to VPC
aws ec2 attach-internet-gateway --vpc-id "$VPC" --internet-gateway-id "$internetGateway"

# Create route table
routeTable=$(aws ec2 create-route-table --vpc-id "$VPC" --query RouteTable.RouteTableId --output text)

# Create default route to Internet Gateway
aws ec2 create-route --route-table-id "$routeTable" --destination-cidr-block 0.0.0.0/0 --gateway-id "$internetGateway"

# Apply route table to subnet0
aws ec2 associate-route-table --subnet-id "$subnet0" --route-table-id "$routeTable"

# Obtain public IP address on launch
aws ec2 modify-subnet-attribute --subnet-id "$subnet0" --map-public-ip-on-launch

# Generate Key Pair
aws ec2 create-key-pair --key-name CSE3SOX-A2-key-pair --query 'KeyMaterial' --output text > ~/.ssh/CSE3SOX-A2-key-pair.pem

# Change permissions of Key Pair
chmod 400 ~/.ssh/CSE3SOX-A2-key-pair.pem



echo "VPC is $VPC"
echo "Subnet0 is $subnet0"
