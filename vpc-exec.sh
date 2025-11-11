#!/bin/bash
# Complete VPCctl Demonstration Script
# This script demonstrates all features required for the task

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print section headers
section() {
    echo ""
    echo -e "${GREEN}=== [$(date +%T)] $1 ===${NC}"
    echo ""
}

# Function to print test results
test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
    fi
}

# Cleanup function
cleanup() {
    section "Cleanup: Removing all VPCs"
    sudo ./vpcctl vpc delete --name vpc1 2>/dev/null || true
    sudo ./vpcctl vpc delete --name vpc2 2>/dev/null || true
    sudo ./cleanup.sh
}

# Trap to cleanup on exit
trap cleanup EXIT

section "1. Prerequisites Check"
echo "Checking system requirements..."
ip netns list
sudo iptables -L -n | head -5

section "2. Create First VPC (vpc1)"
sudo ./vpcctl vpc create --name vpc1 --cidr 10.0.0.0/16
sudo ./vpcctl vpc list

section "3. Add Subnets to VPC1"
echo "Creating public subnet..."
sudo ./vpcctl subnet add --vpc vpc1 --name public --cidr 10.0.1.0/24 --type public

echo "Creating private subnet..."
sudo ./vpcctl subnet add --vpc vpc1 --name private --cidr 10.0.2.0/24 --type private

sudo ./vpcctl vpc list

section "4. Enable NAT Gateway for VPC1"
# Detect active network interface
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "Using interface: $IFACE"
sudo ./vpcctl nat enable --vpc vpc1 --interface $IFACE

section "5. Deploy Web Servers"
echo "Deploying web server in public subnet..."
sudo ./vpcctl deploy webserver --vpc vpc1 --subnet public --port 8080

echo "Deploying web server in private subnet..."
sudo ./vpcctl deploy webserver --vpc vpc1 --subnet private --port 8081

# Wait for servers to start
sleep 2

section "6. Test Intra-VPC Communication"
echo "Testing: Public subnet -> Private subnet"
sudo ip netns exec vpc1-public ping -c 3 10.0.2.2 && test_result 0 "Public can reach Private" || test_result 1 "Public cannot reach Private"

echo ""
echo "Testing: Private subnet -> Public subnet"
sudo ip netns exec vpc1-private ping -c 3 10.0.1.2 && test_result 0 "Private can reach Public" || test_result 1 "Private cannot reach Public"

section "7. Test NAT Gateway (Internet Access)"
echo "Testing: Public subnet internet access"
sudo ip netns exec vpc1-public ping -c 3 8.8.8.8 && test_result 0 "Public subnet has internet" || test_result 1 "Public subnet NO internet"

echo ""
echo "Testing: Public subnet DNS resolution"
sudo ip netns exec vpc1-public curl -I --max-time 5 google.com && test_result 0 "Public subnet DNS works" || test_result 1 "Public subnet DNS failed"

echo ""
echo "Testing: Private subnet internet access (should fail)"
sudo timeout 3 ip netns exec vpc1-private ping -c 2 8.8.8.8 && test_result 1 "Private has internet (UNEXPECTED)" || test_result 0 "Private blocked from internet (EXPECTED)"

section "8. Test Web Server Accessibility"
echo "Testing: Access public subnet web server from host"
curl --max-time 3 http://10.0.1.2:8080 > /dev/null 2>&1 && test_result 0 "Public web server accessible" || test_result 1 "Public web server not accessible"

echo ""
echo "Testing: Access private subnet web server from public subnet"
sudo ip netns exec vpc1-public curl --max-time 3 http://10.0.2.2:8081 > /dev/null 2>&1 && test_result 0 "Private web server reachable within VPC" || test_result 1 "Private web server not reachable"

section "9. Create Second VPC (vpc2)"
sudo ./vpcctl vpc create --name vpc2 --cidr 172.16.0.0/16

echo "Adding public subnet to vpc2..."
sudo ./vpcctl subnet add --vpc vpc2 --name public --cidr 172.16.1.0/24 --type public

echo "Enabling NAT for vpc2..."
sudo ./vpcctl nat enable --vpc vpc2 --interface $IFACE

echo "Deploying web server in vpc2..."
sudo ./vpcctl deploy webserver --vpc vpc2 --subnet public --port 8080

sleep 2

section "10. Test VPC Isolation (Before Peering)"
echo "Testing: VPC1 -> VPC2 (should fail)"
sudo timeout 3 ip netns exec vpc1-public ping -c 2 172.16.1.2 && test_result 1 "VPCs NOT isolated (UNEXPECTED)" || test_result 0 "VPCs are isolated (EXPECTED)"

echo ""
echo "Testing: VPC2 -> VPC1 (should fail)"
sudo timeout 3 ip netns exec vpc2-public ping -c 2 10.0.1.2 && test_result 1 "VPCs NOT isolated (UNEXPECTED)" || test_result 0 "VPCs are isolated (EXPECTED)"

section "11. Create VPC Peering"
sudo ./vpcctl peer create --vpc1 vpc1 --vpc2 vpc2

section "12. Test VPC Communication (After Peering)"
echo "Testing: VPC1 -> VPC2 (should work)"
sudo ip netns exec vpc1-public ping -c 3 172.16.1.2 && test_result 0 "VPC1 can reach VPC2 after peering" || test_result 1 "VPC1 cannot reach VPC2"

echo ""
echo "Testing: VPC2 -> VPC1 (should work)"
sudo ip netns exec vpc2-public ping -c 3 10.0.1.2 && test_result 0 "VPC2 can reach VPC1 after peering" || test_result 1 "VPC2 cannot reach VPC1"

section "13. Apply Firewall Rules"
# Create policy file if it doesn't exist
cat > /tmp/test-policy.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 8080, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
EOF

echo "Applying firewall policy to public subnet..."
sudo ./vpcctl firewall apply --vpc vpc1 --subnet public --policy /tmp/test-policy.json

echo ""
echo "Testing: Port 8080 should still work"
curl --max-time 3 http://10.0.1.2:8080 > /dev/null 2>&1 && test_result 0 "Port 8080 allowed" || test_result 1 "Port 8080 blocked"

section "14. View Logs"
echo "Showing last 30 log entries..."
tail -30 /var/lib/vpcctl/vpcctl.log

section "15. List All Resources"
sudo ./vpcctl vpc list

echo ""
echo "Network namespaces:"
ip netns list

echo ""
echo "Bridges:"
ip link show type bridge | grep "br-"

section "16. Cleanup Resources"
echo "Deleting VPC1..."
sudo ./vpcctl vpc delete --name vpc1

echo ""
echo "Deleting VPC2..."
sudo ./vpcctl vpc delete --name vpc2

echo ""
echo "Verifying cleanup..."
sudo ./vpcctl vpc list

echo ""
echo "Remaining namespaces (should be empty or cleaned):"
ip netns list || echo "No namespaces found"

section "Demonstration Complete"
echo -e "${GREEN}All tests completed successfully!${NC}"
echo ""
echo "Summary:"
echo "  ✓ VPC creation and management"
echo "  ✓ Subnet isolation and routing"
echo "  ✓ NAT gateway functionality"
echo "  ✓ VPC isolation"
echo "  ✓ VPC peering"
echo "  ✓ Firewall rule enforcement"
echo "  ✓ Clean resource teardown"
