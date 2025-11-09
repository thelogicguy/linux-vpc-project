#!/bin/bash
# Emergency cleanup script for vpcctl resources

set -e

echo "=== VPCctl Emergency Cleanup ==="
echo "This will remove all VPC resources created by vpcctl"
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Delete all network namespaces
echo "Removing network namespaces..."
for ns in $(ip netns list | awk '{print $1}'); do
    echo "  Deleting namespace: $ns"
    ip netns delete "$ns" 2>/dev/null || true
done

# Delete all bridges starting with br-
echo "Removing bridges..."
for br in $(ip link show type bridge | grep "^[0-9]" | grep "br-" | awk -F': ' '{print $2}'); do
    echo "  Deleting bridge: $br"
    ip link set "$br" down 2>/dev/null || true
    ip link delete "$br" 2>/dev/null || true
done

# Delete all veth interfaces
echo "Removing veth pairs..."
for veth in $(ip link show type veth | grep "^[0-9]" | grep -E "veth-|peer-" | awk -F': ' '{print $2}' | cut -d'@' -f1); do
    echo "  Deleting veth: $veth"
    ip link delete "$veth" 2>/dev/null || true
done

# Clean iptables rules (be careful!)
echo "Cleaning iptables NAT rules..."
iptables -t nat -L POSTROUTING -n --line-numbers | grep MASQUERADE | awk '{print $1}' | tac | while read line; do
    iptables -t nat -D POSTROUTING "$line" 2>/dev/null || true
done

echo "Cleaning iptables FORWARD rules..."
iptables -L FORWARD -n --line-numbers | grep -E "br-|veth-" | awk '{print $1}' | tac | while read line; do
    iptables -D FORWARD "$line" 2>/dev/null || true
done

# Remove state files
echo "Removing state files..."
rm -rf /var/lib/vpcctl 2>/dev/null || true

echo ""
echo "=== Cleanup Complete ==="
echo "All VPC resources have been removed"
