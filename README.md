# ☁️vpcctl: Build Your Own VPC on Linux

## Overview

This project implements a custom **Command Line Interface (CLI) tool** called `vpcctl` that simulates the core functionality of a **Virtual Private Cloud (VPC)** using native **Linux networking primitives**.

It recreates essential cloud networking features, including:
* VPC creation and isolation
* Subnet isolation (public/private)
* Intra-VPC routing
* NAT gateways for controlled internet access
* VPC peering for inter-VPC communication
* Firewall rules (Security Groups)

The tool is built entirely in **Python** and relies on standard Linux utilities like `ip` (for network namespaces, veth pairs, bridges, routing) and `iptables` (for NAT and firewalling).

This project was developed as part of the **HNG Internship Stage 4 Task: Build Your Own VPC on Linux**. The goal is to demonstrate **Linux networking fundamentals from first principles**, including network namespaces for isolation, bridges as virtual routers, and controlled traffic flow—effectively **mirroring cloud VPC behavior on a single host**.

**Note:** No third-party networking libraries are used. All commands are **idempotent** (safe for repeated runs) and actions are logged for transparency.



##  Features

* **VPC Creation & Management:** Create, delete, and list VPCs with custom CIDR ranges.
* **Subnets:** Add public/private subnets represented as **network namespaces**, connected via **veth pairs** to a central bridge (the VPC's "router").
* **Intra-VPC Routing:** Automatic routing and communication between subnets within the same VPC.
* **NAT Gateway:** Enable outbound internet access for **public subnets only** via `iptables` MASQUERADE; private subnets remain isolated.
* **VPC Isolation:** Multiple VPCs are **fully isolated** by default—preventing any unauthorized cross-VPC traffic.
* **VPC Peering:** Optional peering connects VPCs via **veth pairs and static routes** for controlled, private communication.
* **Firewall Rules:** Apply JSON-based security group policies using **iptables** within the subnet namespaces (e.g., allow/deny ports and protocols).
* **Test Workloads:** Deploy simple Python web servers into subnets for immediate connectivity testing.
* **Cleanup & Logging:** Complete and clean teardown of all resources (namespaces, bridges, veths, rules). All actions are logged to `/var/lib/vpcctl/vpcctl.log`.

---

##  Requirements & Installation

### Requirements

| Requirement | Details |
| :--- | :--- |
| **OS** | Linux (tested on Ubuntu/Debian; requires kernel support for namespaces and bridges). |
| **Privileges** | Must be run as **root** (`sudo`) for network configuration. |
| **Tools** | `ip` (`iproute2`), `iptables`, **Python 3.6+** (standard libraries only). |
| **Dependencies** | **None.** No `pip install` required; uses built-in Python modules. |

### Installation

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/yourusername/hng-4-vpc.git](https://github.com/yourusername/hng-4-vpc.git)
    cd hng-4-vpc
    ```
2.  **Make the CLI executable:**
    ```bash
    chmod +x vpcctl
    chmod +x demo.sh
    chmod +x cleanup.sh
    ```
3.  **(Optional) Create a sample policy file for firewall demo:**
    ```bash
    cat > policy.json <<EOF
    {
      "subnet": "10.0.1.0/24",
      "ingress": [
        {"port": 8080, "protocol": "tcp", "action": "allow"},
        {"port": 22, "protocol": "tcp", "action": "deny"}
      ]
    }
    EOF
    ```


##  Usage

Run all commands using **`sudo ./vpcctl [command]`**. Root privileges are mandatory for network configuration.

### CLI Commands

| Operation | Command | Description |
| :--- | :--- | :--- |
| **VPC Create** | `sudo ./vpcctl vpc create --name vpc1 --cidr 10.0.0.0/16` | Creates a new VPC bridge and initializes state. |
| **VPC List** | `sudo ./vpcctl vpc list` | Lists all active VPCs. |
| **VPC Delete** | `sudo ./vpcctl vpc delete --name vpc1` | Tears down and deletes a VPC and all its resources. |
| **Subnet Add** | `sudo ./vpcctl subnet add --vpc vpc1 --name public --cidr 10.0.1.0/24 --type public` | Creates a new network namespace (subnet). |
| **NAT Enable** | `sudo ./vpcctl nat enable --vpc vpc1 --interface eth0` | Enables NAT for public subnets (replace `eth0` with your host's internet interface). |
| **VPC Peering** | `sudo ./vpcctl peer create --vpc1 vpc1 --vpc2 vpc2` | Creates a peering connection between two existing VPCs. |
| **Firewall Apply** | `sudo ./vpcctl firewall apply --vpc vpc1 --subnet public --policy policy.json` | Applies security group rules to a subnet namespace. |
| **Deploy Workload**| `sudo ./vpcctl deploy webserver --vpc vpc1 --subnet public --port 8080` | Starts a simple HTTP server in the target subnet namespace. |

### Full Demo

For a complete end-to-end demonstration (creating resources, running connectivity tests, applying firewall, and cleanup):

```bash
./demo.sh
````

*(Note: `demo.sh` runs commands using `sudo` internally.)*



##  Architecture

The VPC simulation leverages these core Linux networking concepts:

| Component | Linux Primitive | Role |
| :--- | :--- | :--- |
| **VPC** | **Linux Bridge** (`br-vpcX`) | Acts as the central **VPC router/gateway** with the VPC's gateway IP (e.g., `10.0.0.1`). |
| **Subnets** | **Network Namespaces** (`vpcX-subnetY`) | Provides **network isolation** for the subnet/workloads. |
| **Connection** | **Veth Pairs** | Connects the Subnet Namespace to the VPC Bridge. |
| **Routing** | **Static Routes** | Default routes in namespaces point to the bridge gateway. |
| **NAT** | **`iptables` MASQUERADE** | Enables outbound internet access for selected (public) subnets. |
| **Peering** | **Veth Pair + Static Routes** | Connects two VPC bridges for controlled inter-VPC communication. |
| **Firewall** | **`iptables` Rules** | Per-subnet security group rules applied within the namespace. |
| **State** | **`/var/lib/vpcctl/state.json`** | Persists resource metadata for idempotency and safe cleanup. |

### Text-Based Diagram

```text
Host Machine
├── Bridge (br-vpc1, Gateway: 10.0.0.1) 
│   ├── Veth Pair → Namespace (vpc1-public, IP: 10.0.1.2) - NAT enabled
│   └── Veth Pair → Namespace (vpc1-private, IP: 10.0.2.2) - Isolated
├── Peering Veth Pair → Bridge (br-vpc2)
└── iptables (NAT for public, Forwarding Rules on host)
```



##  Testing & Validation

You can validate the implementation by running the full demo script:

```bash
./demo.sh
```

The script will perform and validate tests for:

  * Creation of all resources (VPCs, subnets).
  * Deployment of test web servers.
  * **Intra-VPC** connectivity (subnet-to-subnet ping/curl).
  * **Internet Access** (NAT functionality from public subnet).
  * **VPC Isolation** (ensuring no traffic between non-peered VPCs).
  * **VPC Peering** (successful traffic between peered VPCs).
  * **Firewall** (testing allow/deny rules).
  * Cleanup (verification that no orphaned resources remain).

**Expected output:** The script should conclude with **All green checkmarks (✓)** for successes.

**Logs:** Review all actions and system outputs in the log file:

```bash
tail /var/lib/vpcctl/vpcctl.log
```


##  Cleanup

For an emergency or complete reset of all resources created by `vpcctl`:

```bash
sudo ./cleanup.sh
```

*You will be prompted to confirm the deletion.*

This script aggressively deletes all known namespaces, bridges, veth pairs, iptables rules, and state files created by the tool, ensuring a clean system state.

