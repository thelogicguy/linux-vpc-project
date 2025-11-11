#!/bin/bash

# VPCctl Manual Demo for Recording
# Time: ~5 minutes

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  VPC Cloud on Linux - HNG Stage 4 Task ║${NC}"
echo -e "${GREEN}║  By: Macdonald Daniel                  ║${NC}"
echo -e "${GREEN}║  Time: $(date +%H:%M:%S)               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
sleep 2

# ============== SECTION 1: VPC CREATION ==============
echo -e "${BLUE}[00:30] SECTION 1: Creating VPC Infrastructure${NC}"
echo ""
sleep 2

echo -e "${YELLOW}→ Creating VPC1 with CIDR 10.0.0.0/16${NC}"
sudo ./vpcctl vpc create --name vpc1 --cidr 10.0.0.0/16
echo ""
sleep 5

echo -e "${YELLOW}→ Adding Public Subnet (10.0.1.0/24)${NC}"
sudo ./vpcctl subnet add --vpc vpc1 --name public --cidr 10.0.1.0/24 --type public
echo ""
sleep 5

echo -e "${YELLOW}→ Adding Private Subnet (10.0.2.0/24)${NC}"
sudo ./vpcctl subnet add --vpc vpc1 --name private --cidr 10.0.2.0/24 --type private
echo ""
sleep 5

echo -e "${YELLOW}→ Listing VPC Configuration${NC}"
sudo ./vpcctl vpc list
echo ""
sleep 5

# ============== SECTION 2: NAT GATEWAY ==============
echo -e "${BLUE}[01:30] SECTION 2: Enabling NAT Gateway${NC}"
echo ""
sleep 1

IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo -e "${YELLOW}→ Detecting network interface: $IFACE${NC}"
sleep 2

echo -e "${YELLOW}→ Enabling NAT for public subnet${NC}"
sudo ./vpcctl nat enable --vpc vpc1 --interface $IFACE
echo ""
sleep 4

# ============== SECTION 3: DEPLOY WORKLOADS ==============
echo -e "${BLUE}[02:00] SECTION 3: Deploying Test Web Servers${NC}"
echo ""
sleep 4

echo -e "${YELLOW}→ Deploying web server in PUBLIC subnet (port 8080)${NC}"
sudo ./vpcctl deploy webserver --vpc vpc1 --subnet public --port 8080
echo ""
sleep 4

echo -e "${YELLOW}→ Deploying web server in PRIVATE subnet (port 8081)${NC}"
sudo ./vpcctl deploy webserver --vpc vpc1 --subnet private --port 8081
echo ""
sleep 4

# ============== SECTION 4: CONNECTIVITY TESTS ==============
echo -e "${BLUE}[02:30] SECTION 4: Testing Connectivity${NC}"
echo ""
sleep 1

echo -e "${YELLOW}→ Test 1: Public subnet → Private subnet (Intra-VPC)${NC}"
sudo ip netns exec vpc1-public ping -c 3 10.0.2.2
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS: Intra-VPC communication works${NC}"
else
    echo -e "${RED}❌ FAILED${NC}"
fi
echo ""
sleep 4

echo -e "${YELLOW}→ Test 2: Public subnet → Internet (via NAT)${NC}"
sudo ip netns exec vpc1-public ping -c 3 8.8.8.8
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS: Public subnet has internet access${NC}"
else
    echo -e "${RED}❌ FAILED${NC}"
fi
echo ""
sleep 4

echo -e "${YELLOW}→ Test 3: Private subnet → Internet (should FAIL)${NC}"
sudo timeout 3 ip netns exec vpc1-private ping -c 2 8.8.8.8
if [ $? -ne 0 ]; then
    echo -e "${GREEN}✅ SUCCESS: Private subnet correctly blocked from internet${NC}"
else
    echo -e "${RED}❌ UNEXPECTED: Private subnet has internet access${NC}"
fi
echo ""
sleep 4

echo -e "${YELLOW}→ Test 4: Accessing public web server from host${NC}"
curl -s http://10.0.1.2:8080 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS: Public web server accessible${NC}"
else
    echo -e "${RED}❌ FAILED${NC}"
fi
echo ""
sleep 4

# ============== SECTION 5: SECOND VPC & ISOLATION ==============
echo -e "${BLUE}[03:30] SECTION 5: VPC Isolation Test${NC}"
echo ""
sleep 1

echo -e "${YELLOW}→ Creating VPC2 (172.16.0.0/16)${NC}"
sudo ./vpcctl vpc create --name vpc2 --cidr 172.16.0.0/16
echo ""
sleep 4

echo -e "${YELLOW}→ Adding public subnet to VPC2${NC}"
sudo ./vpcctl subnet add --vpc vpc2 --name public --cidr 172.16.1.0/24 --type public
echo ""
sleep 4

echo -e "${YELLOW}→ Enabling NAT for VPC2${NC}"
sudo ./vpcctl nat enable --vpc vpc2 --interface $IFACE
echo ""
sleep 4

echo -e "${YELLOW}→ Test 5: VPC1 → VPC2 (should FAIL - isolated)${NC}"
sudo timeout 3 ip netns exec vpc1-public ping -c 2 172.16.1.2
if [ $? -ne 0 ]; then
    echo -e "${GREEN}✅ SUCCESS: VPCs are properly isolated${NC}"
else
    echo -e "${RED}❌ UNEXPECTED: VPCs can communicate${NC}"
fi
echo ""
sleep 4

# ============== SECTION 6: VPC PEERING ==============
echo -e "${BLUE}[04:00] SECTION 6: Creating VPC Peering${NC}"
echo ""
sleep 1

echo -e "${YELLOW}→ Creating peering connection between VPC1 and VPC2${NC}"
sudo ./vpcctl peer create --vpc1 vpc1 --vpc2 vpc2
echo ""
sleep 4

echo -e "${YELLOW}→ Test 6: VPC1 → VPC2 (should now WORK)${NC}"
sudo ip netns exec vpc1-public ping -c 3 172.16.1.2
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS: Peering enabled cross-VPC communication${NC}"
else
    echo -e "${RED}❌ FAILED${NC}"
fi
echo ""
sleep 4

# ============== SECTION 7: FIREWALL RULES ==============
echo -e "${BLUE}[04:30] SECTION 7: Applying Firewall Rules${NC}"
echo ""
sleep 1

cat > /tmp/firewall-policy.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 8080, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
EOF

echo -e "${YELLOW}→ Firewall Policy:${NC}"
cat /tmp/firewall-policy.json
echo ""
sleep 4

echo -e "${YELLOW}→ Applying firewall policy to public subnet${NC}"
sudo ./vpcctl firewall apply --vpc vpc1 --subnet public --policy /tmp/firewall-policy.json
echo ""
sleep 4

echo -e "${YELLOW}→ Test 7: Accessing port 8080 (allowed)${NC}"
curl -s http://10.0.1.2:8080 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SUCCESS: Port 8080 accessible${NC}"
else
    echo -e "${RED}❌ FAILED${NC}"
fi
echo ""
sleep 4

# ============== SECTION 8: SHOW LOGS ==============
echo -e "${BLUE}[04:45] SECTION 8: Viewing Logs${NC}"
echo ""
sleep 1

echo -e "${YELLOW}→ Last 20 log entries:${NC}"
tail -20 /var/lib/vpcctl/vpcctl.log
echo ""
sleep 5

# ============== SECTION 9: RESOURCE LISTING ==============
echo -e "${BLUE}[04:50] SECTION 9: Listing All Resources${NC}"
echo ""
sleep 1

echo -e "${YELLOW}→ VPC List:${NC}"
sudo ./vpcctl vpc list
echo ""
sleep 4

echo -e "${YELLOW}→ Network Namespaces:${NC}"
ip netns list
echo ""
sleep 4

echo -e "${YELLOW}→ Bridge Interfaces:${NC}"
ip link show type bridge | grep -E "^[0-9]+:" | awk -F': ' '{print $2}'
echo ""
sleep 4

# ============== SECTION 10: CLEANUP ==============
echo -e "${BLUE}[04:55] SECTION 10: Cleanup${NC}"
echo ""
sleep 1

echo -e "${YELLOW}→ Deleting VPC1...${NC}"
sudo ./vpcctl vpc delete --name vpc1
echo ""
sleep 4

echo -e "${YELLOW}→ Deleting VPC2...${NC}"
sudo ./vpcctl vpc delete --name vpc2
echo ""
sleep 4

echo -e "${YELLOW}→ Verifying cleanup...${NC}"
sudo ./vpcctl vpc list
echo ""
ip netns list
echo ""
sleep 4

# ============== FINAL SUMMARY ==============
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Demo Complete!                 ║${NC}"
echo -e "${GREEN}║                                        ║${NC}"
echo -e "${GREEN}║  ✅ VPC Creation                       ║${NC}"
echo -e "${GREEN}║  ✅ Subnet Isolation                   ║${NC}"
echo -e "${GREEN}║  ✅ NAT Gateway                        ║${NC}"
echo -e "${GREEN}║  ✅ VPC Isolation                      ║${NC}"
echo -e "${GREEN}║  ✅ VPC Peering                        ║${NC}"
echo -e "${GREEN}║  ✅ Firewall Rules                     ║${NC}"
echo -e "${GREEN}║  ✅ Clean Teardown                     ║${NC}"
echo -e "${GREEN}║                                        ║${NC}"
echo -e "${GREEN}║  Time: $(date +%H:%M:%S)                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
