#!/bin/bash

# Create log file
runDate=$(date +"%Y%m%d-%H%M")
logFile=~/$0-$runDate
echo "Script Starting @ $runDate" > $logFile

# Create VPC
VPC=$(aws ec2 create-vpc --cidr-block 172.16.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Task3VPC}]' --query Vpc.VpcId --output text)

# Create subnets in the new VPC
subnet0=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.0.0/24 --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Subnet0 Public}]' --availability-zone us-east-1a --query Subnet.SubnetId --output text)
subnet1=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.1.0/24 --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Subnet1 Private}]' --availability-zone us-east-1a --query Subnet.SubnetId --output text)
subnet2=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 172.16.2.0/24 --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Subnet2 Public}]' --availability-zone us-east-1b --query Subnet.SubnetId --output text)

# Determine the route table id for the VPC
PubRouteTable=$(aws ec2 describe-route-tables --query "RouteTables[?VpcId == '$VPC'].RouteTableId" --output text)

# Update tag
aws ec2 create-tags --resources $PubRouteTable --tags 'Key=Name,Value=Public route Table'

# Create private route table
PrivRouteTable=$(aws ec2 create-route-table --vpc-id "$VPC" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Private Route Table}]' --query RouteTable.RouteTableId --output text)

# Create Internet Gateway
internetGateway=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=Task3-igw}]' --query InternetGateway.InternetGatewayId --output text)

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

# Create Security Group for public host
webAppSG=$(aws ec2 create-security-group --group-name webApp-sg --description "Security group for host in public subnet" --vpc-id "$VPC" --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=Public HostSG}]' --query 'GroupId' --output text)
 
# Create Security Group for private host
privateHostSG=$(aws ec2 create-security-group --group-name privateHost-sg --description "Security group for host in private subnet" --vpc-id "$VPC" --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=Private HostSG}]' --query 'GroupId' --output text)

# Allow SSH and http traffic
aws ec2 authorize-security-group-ingress --group-id "$webAppSG" --protocol tcp --port 22 --cidr 0.0.0.0/0 --query 'Return' --output text
aws ec2 authorize-security-group-ingress --group-id "$webAppSG" --protocol tcp --port 80 --cidr 0.0.0.0/0 --query 'Return' --output text

# Allow SSH from private subnet
aws ec2 authorize-security-group-ingress --group-id "$privateHostSG" --protocol tcp --port 22 --source-group "$webAppSG"  --query 'Return' --output text
aws ec2 authorize-security-group-ingress --group-id "$privateHostSG" --protocol tcp --port 3306 --source-group "$webAppSG"  --query 'Return' --output text

# Create EC2 Instance in public subnet "Public Host1" - Uses golden image created in task 1
pubHost1ID=$(aws ec2 run-instances --image-id ami-08a85687358dd743b --count 1 --instance-type t2.micro --key-name CSE3SOX-A2-key-pair --security-group-ids "$webAppSG" --subnet-id "$subnet0" --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Public Host1}]' --query Instances[].InstanceId --output text)

# Create EC2 Instance in public subnet "Public Host2" - Uses golden image created in task 1
pubHost2ID=$(aws ec2 run-instances --image-id ami-08a85687358dd743b --count 1 --instance-type t2.micro --key-name CSE3SOX-A2-key-pair --security-group-ids "$webAppSG" --subnet-id "$subnet0" --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Public Host2}]' --query Instances[].InstanceId --output text)

# Create EC2 Instance in private subnet - Uses golden image created in task 1
privEC2ID=$(aws ec2 run-instances --image-id ami-08a85687358dd743b --count 1 --instance-type t2.micro --key-name CSE3SOX-A2-key-pair  --security-group-ids "$privateHostSG" --subnet-id "$subnet1" --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Private Host1}]' --query Instances[].InstanceId --output text)

# Determine public IP address of EC2 instance
publicIP1=$(aws ec2 describe-instances --instance-ids "$pubHost1ID" --query Reservations[].Instances[].PublicIpAddress  --output text)

# Determine public IP address of EC2 instance
publicIP2=$(aws ec2 describe-instances --instance-ids "$pubHost2ID" --query Reservations[].Instances[].PublicIpAddress  --output text)

# Determine private IP address of EC2 instance
privateIP=$(aws ec2 describe-instances --instance-ids "$privEC2ID" --query Reservations[].Instances[].PrivateIpAddress  --output text)

#############
#
# Create Elastic Load Balancer
elbv2ARN=$(aws elbv2 create-load-balancer --name Task3-elb3 --subnets "$subnet0" "$subnet2" --security-groups "$webAppSG" --query LoadBalancers[].LoadBalancerArn --output text)

# Create target group for public EC2 instances
targetGroupARN=$(aws elbv2 create-target-group --name Task3-web-targets --protocol HTTP --port 80 --vpc-id "$VPC" --ip-address-type ipv4 --query TargetGroups[].TargetGroupArn --output text)

# Add public EC2 instances to target group
aws elbv2 register-targets --target-group-arn "$targetGroupARN" --targets Id=$pubHost1ID Id=$pubHost2ID

# Create listener on load balancer
aws elbv2 create-listener --load-balancer-arn "$elbv2ARN" --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$targetGroupARN

# Determine DNS name
webURL=$(aws elbv2 describe-load-balancers --load-balancer-arns "$elbv2ARN" --query LoadBalancers[].DNSName --output text)

#
#############

# Script complete message
greenText='\033[0;32m'
NC='\033[0m' # No Color
echo "Connect to pubilc EC2 instances using the command below"
echo -e "\n${greenText}\t\t ssh -i ~/.ssh/CSE3SOX-A2-key-pair.pem ec2-user@$publicIP1 ${NC}"
echo -e "${greenText}\t\t ssh -i ~/.ssh/CSE3SOX-A2-key-pair.pem ec2-user@$publicIP2 ${NC}\n"
echo "Connect to private EC2 instance using the command below"
echo -e "\n${greenText}\t\t ssh -i ~/.ssh/CSE3SOX-A2-key-pair.pem ec2-user@$privateIP ${NC}\n"
echo "Connect to website using the url below"
echo -e "\n${greenText}\t\t http://"$elbv2ARN" ${NC}\n"