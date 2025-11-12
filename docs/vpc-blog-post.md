# Building Your Own Virtual Private Cloud on Linux: A Complete Hands-On Guide

*Ever wondered how AWS creates those isolated networks? Let's build one ourselves using nothing but Linux!*

**By Macdonald Daniel**

---

## Hey There! 👋

So, you've probably used AWS or heard about VPCs (Virtual Private Clouds), right? They're these magical isolated networks where you can run your applications safely. But have you ever thought, "How does this actually work under the hood?"

Well, I recently went down that rabbit hole, and guess what? We can actually build our own VPC right on a Linux machine! No AWS account needed, no credit card, just your computer and some curiosity.

In this guide, I'll walk you through building `vpcctl`—a command-line tool that recreates AWS VPC functionality using pure Linux networking. We're talking subnets, NAT gateways, VPC peering, the whole deal. And the best part? You'll actually understand how cloud networking works by the time we're done.

**What you'll learn:**
- How cloud providers isolate customer networks
- Linux networking magic (namespaces, bridges, and more)
- How NAT gateways actually work
- Building network infrastructure from scratch

Don't worry if you're new to this stuff. I'll explain everything as we go!

---

## Before We Start

Here's what you'll need:

**The Essentials:**
- A Linux machine (I used Ubuntu 20.04, but most distros work)
- Root access (we'll be using `sudo` a lot)
- Python 3.6 or newer (probably already installed)
- Basic familiarity with the command line

**Quick check—do you have the tools?**
```bash
which ip iptables python3
```

If something's missing, no worries:
```bash
sudo apt-get update
sudo apt-get install iproute2 iptables python3
```

That's it! We're keeping this simple—no fancy dependencies or complicated setups.

---

## What Are We Actually Building?

Let me paint you a picture. When you create a VPC in AWS, you're essentially getting a private network that's completely isolated from everyone else's stuff. Inside this VPC, you can create subnets (like different floors in a building), set up routing (how traffic flows), and control internet access.

**The main components:**
- **VPC**: Your isolated network (think: `10.0.0.0/16`)
- **Subnets**: Smaller networks within the VPC (like `10.0.1.0/24`)
- **Router/Gateway**: Directs traffic between subnets
- **NAT Gateway**: Lets your private resources talk to the internet
- **Security Groups**: Firewall rules (who can talk to whom)

Now here's the cool part—we can simulate all of this using Linux primitives!

### The Linux Magic

| What AWS Calls It | What We'll Use | Why It Works |
|-------------------|----------------|--------------|
| VPC | Linux Bridge | Acts like a virtual switch and router |
| Subnet | Network Namespace | Complete network isolation (separate IP stack!) |
| Connection | Veth Pair | Like a virtual ethernet cable |
| NAT Gateway | iptables | Changes IP addresses on the fly |
| Security Groups | iptables Rules | Filters packets going in and out |
| VPC Peering | Veth Pair + Routes | Connects two isolated networks |

---

## The Big Picture: Our Architecture

Let me show you what we're building. Imagine this setup:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Your Linux Machine                            │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              VPC 1 (10.0.0.0/16)                          │  │
│  │                                                            │  │
│  │        ┌──────────────────────────┐                       │  │
│  │        │   Linux Bridge           │                       │  │
│  │        │   br-vpc1                │                       │  │
│  │        │   Gateway: 10.0.0.1      │◄──── sends traffic    │  │
│  │        └──────┬──────────┬────────┘      to internet      │  │
│  │               │          │                                 │  │
│  │        veth   │          │   veth                         │  │
│  │        pair   │          │   pair                         │  │
│  │               ▼          ▼                                 │  │
│  │    ┌──────────────┐  ┌──────────────┐                    │  │
│  │    │ Public       │  │ Private      │                    │  │
│  │    │ Subnet       │  │ Subnet       │                    │  │
│  │    │ 10.0.1.2     │  │ 10.0.2.2     │                    │  │
│  │    │              │  │              │                    │  │
│  │    │ ✓ Can reach  │  │ ✗ Locked     │                    │  │
│  │    │   internet   │  │   down       │                    │  │
│  │    │ Web Server   │  │ Database     │                    │  │
│  │    └──────────────┘  └──────────────┘                    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                     Can connect these                            │
│                       if we want!                                │
│                            │                                     │
│  ┌────────────────────────▼──────────────────────────────────┐  │
│  │              VPC 2 (172.16.0.0/16)                        │  │
│  │        ┌──────────────────────────┐                       │  │
│  │        │   Linux Bridge           │                       │  │
│  │        │   br-vpc2                │                       │  │
│  │        │   Gateway: 172.16.0.1    │                       │  │
│  │        └──────────────────────────┘                       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│              ┌─────────────────┐                                 │
│              │   iptables      │                                 │
│              │   (the magic    │                                 │
│              │    NAT box)     │                                 │
│              └────────┬────────┘                                 │
│                       │                                           │
│              ┌────────▼────────┐                                 │
│              │ Your WiFi/      │                                 │
│              │ Ethernet        │                                 │
│              └────────┬────────┘                                 │
└───────────────────────┼──────────────────────────────────────────┘
                        │
                        ▼
                  The Internet 🌐
```

**How traffic actually flows:**

When your public subnet wants to reach the internet:
1. Packet starts in the namespace (your subnet)
2. Goes through the veth pair to the bridge
3. Bridge forwards to iptables
4. iptables does NAT magic (changes your private IP to the public IP)
5. Heads out through your actual network interface
6. Comes back the same way, but reversed!

Meanwhile, your private subnet? It just sits there, happily isolated, with no route to the internet. Perfect for databases and sensitive stuff!

---

## Let's Get This Thing Running

### Grab the Code

First, let's get the project:

```bash
git clone https://github.com/yourusername/hng-4-vpc.git
cd hng-4-vpc

# Make everything executable
chmod +x vpcctl demo.sh cleanup.sh
```

### Quick Sanity Check

```bash
sudo ./vpcctl --help
```

If you see a bunch of commands listed, you're good to go!

---

## Building Our First VPC (The Fun Part!)

Alright, let's actually build something. We'll create a VPC with both public and private subnets, just like you would in AWS.

### Step 1: Create the VPC

```bash
sudo ./vpcctl vpc create --name myvpc --cidr 10.0.0.0/16
```

**What just happened?**
The tool created a Linux bridge called `br-myvpc` and gave it the IP `10.0.0.1`. This bridge is going to be our VPC's router. Everything in our VPC will use this as their gateway.

Want to see it? Run this:
```bash
ip link show br-myvpc
```

Cool, right?

### Step 2: Add a Public Subnet

Now let's create a subnet that can reach the internet:

```bash
sudo ./vpcctl subnet add --vpc myvpc --name public --cidr 10.0.1.0/24 --type public
```

**Behind the scenes:**
- Created a network namespace (think: a completely separate network stack)
- Made a veth pair (virtual ethernet cable)
- Plugged one end into the namespace, other end into our bridge
- Gave the namespace the IP `10.0.1.2`
- Set the default route to point to our bridge gateway

Check it out:
```bash
# See all namespaces
sudo ip netns list

# Look inside the namespace
sudo ip netns exec myvpc-public ip addr
```

Mind-blowing, isn't it? We just created a completely isolated network!

### Step 3: Add a Private Subnet

Let's add a subnet that stays locked down:

```bash
sudo ./vpcctl subnet add --vpc myvpc --name private --cidr 10.0.2.0/24 --type private
```

Same deal, but this one gets IP `10.0.2.2` and won't have internet access.

### Step 4: Turn On the Internet

Here's where it gets interesting. First, figure out which network interface connects your computer to the internet:

```bash
ip route | grep default
```

Look for something like `eth0`, `ens33`, or `wlan0`. Got it? Now:

```bash
# Replace eth0 with whatever you found
sudo ./vpcctl nat enable --vpc myvpc --interface eth0
```

**What's NAT doing?**
It's basically lying to the internet! When your public subnet sends packets out, NAT changes the source IP from `10.0.1.2` (private) to your computer's real IP address. When replies come back, it changes them back. The internet never knows about your private network!

---

## Does It Actually Work? Let's Find Out!

Time for the moment of truth. Let's test everything!

### Test #1: Can Subnets Talk to Each Other?

```bash
sudo ip netns exec myvpc-public ping -c 3 10.0.2.2
```

You should see something like:
```
64 bytes from 10.0.2.2: icmp_seq=1 ttl=64 time=0.123 ms
```

Success! The subnets can talk through the bridge. This is intra-VPC routing in action!

### Test #2: Can We Reach the Internet?

```bash
sudo ip netns exec myvpc-public ping -c 3 8.8.8.8
```

If you see replies from Google's DNS server, congratulations—your NAT gateway works!

Try something fancier:
```bash
sudo ip netns exec myvpc-public curl -I https://google.com
```

Getting HTTP headers back? Beautiful!

### Test #3: Is the Private Subnet Really Private?

```bash
sudo ip netns exec myvpc-private ping -c 3 8.8.8.8
```

This should timeout or fail. If it does, perfect! Your private subnet is properly isolated from the internet. This is exactly what we want for security.

### Test #4: Let's Run a Web Server

Now for something cool. Let's deploy a web server in our public subnet:

```bash
sudo ./vpcctl deploy webserver --vpc myvpc --subnet public --port 8080
```

Now test it from your host machine:
```bash
curl http://10.0.1.2:8080
```

You should see a simple HTML page! 

Can the private subnet reach it?
```bash
sudo ip netns exec myvpc-private curl http://10.0.1.2:8080
```

Yep! Internal traffic works fine.

### Test #5: Are VPCs Really Isolated?

Let's create another VPC and see if they can talk:

```bash
# Create VPC 2
sudo ./vpcctl vpc create --name vpc2 --cidr 172.16.0.0/16
sudo ./vpcctl subnet add --vpc vpc2 --name subnet1 --cidr 172.16.1.0/24 --type public
```

Now try to ping from VPC1 to VPC2:
```bash
sudo ip netns exec myvpc-public ping -c 3 172.16.1.2
```

Fails, right? That's VPC isolation at work! Just like in AWS, VPCs can't talk to each other by default.

### Test #6: VPC Peering Time!

But what if we want them to communicate? Let's create a peering connection:

```bash
sudo ./vpcctl peer create --vpc1 myvpc --vpc2 vpc2
```

Now try that ping again:
```bash
sudo ip netns exec myvpc-public ping -c 3 172.16.1.2
```

Magic! It works now. The peering created a direct connection between the two VPC bridges.

### Test #7: Security Groups (Firewall Rules)

Let's lock down our public subnet. Create a policy file:

```bash
cat > my-firewall.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 8080, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
EOF
```

Apply it:
```bash
sudo ./vpcctl firewall apply --vpc myvpc --subnet public --policy my-firewall.json
```

Now port 8080 is open (for our web server) but port 22 is blocked (no SSH). Try testing both!

---

## Real-World Example: A Web App Setup

Let me show you how you'd actually use this for a real application:

```bash
# Create a VPC for your web app
sudo ./vpcctl vpc create --name webapp --cidr 10.0.0.0/16

# Public subnet for web servers (internet-facing)
sudo ./vpcctl subnet add --vpc webapp --name web --cidr 10.0.1.0/24 --type public

# Private subnet for database (locked down)
sudo ./vpcctl subnet add --vpc webapp --name db --cidr 10.0.2.0/24 --type private

# Turn on internet for the web tier
sudo ./vpcctl nat enable --vpc webapp --interface eth0

# Deploy the web server
sudo ./vpcctl deploy webserver --vpc webapp --subnet web --port 8080

# Set up firewall rules
cat > web-rules.json <<EOF
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 443, "protocol": "tcp", "action": "allow"},
    {"port": 8080, "protocol": "tcp", "action": "allow"}
  ]
}
EOF

sudo ./vpcctl firewall apply --vpc webapp --subnet web --policy web-rules.json
```

Now you've got:
- Web servers that can reach the internet ✓
- A database subnet that's completely isolated ✓
- Firewall rules protecting your web tier ✓
- Internal communication between web and database ✓

Just like a real production setup!

---

## When Things Go Wrong (And They Will!)

Here are the issues I ran into and how I fixed them:

### "Permission denied"

Forgot to use `sudo`? Yeah, me too. Always use:
```bash
sudo ./vpcctl [your command]
```

### Subnets Can't Talk to Each Other

Check if your bridge is actually up:
```bash
ip link show br-myvpc
```

If it says "DOWN", fix it:
```bash
sudo ip link set br-myvpc up
```

### No Internet Access

First, check if NAT rules exist:
```bash
sudo iptables -t nat -L -n | grep 10.0
```

Nothing there? You might need to re-enable NAT. Also check:
```bash
cat /proc/sys/net/ipv4/ip_forward
```

If that's `0`, turn it on:
```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

### Something's Completely Broken

When in doubt, nuke everything and start fresh:
```bash
sudo ./cleanup.sh
```

This deletes all VPC resources. It's like hitting the reset button.

---

## Checking the Logs

Everything gets logged to `/var/lib/vpcctl/vpcctl.log`. Super useful when debugging:

```bash
# Watch logs in real-time
sudo tail -f /var/lib/vpcctl/vpcctl.log

# Find errors
sudo grep ERROR /var/lib/vpcctl/vpcctl.log

# See all commands that ran
sudo grep "Executing" /var/lib/vpcctl/vpcctl.log
```

---

## Cleaning Up Your Mess

### Delete One VPC

```bash
sudo ./vpcctl vpc delete --name myvpc
```

This removes the VPC and all its subnets, routes, everything.

### Nuclear Option: Delete Everything

```bash
sudo ./cleanup.sh
```

This removes ALL VPC resources from your system. You'll get a confirmation prompt, so don't worry about accidentally nuking everything.

After cleanup, verify nothing's left:
```bash
sudo ip netns list | grep vpc
sudo ip link show | grep br-vpc
```

Should be empty!

---

## What You Just Learned

Okay, so we've built a lot here. Let's recap:

**Linux Networking:**
- Network namespaces give you complete network isolation
- Bridges work like virtual switches and routers
- Veth pairs are virtual ethernet cables
- iptables can do NAT and firewalling
- Static routes control how packets flow

**Cloud Concepts:**
- VPCs create isolated virtual networks
- Subnets segment your network for organization and security
- NAT gateways give private resources controlled internet access
- Security groups act as virtual firewalls
- VPC peering connects isolated networks

**Practical Skills:**
- You can build infrastructure from scratch
- You understand how cloud providers work under the hood
- You can debug network issues
- You've created actual infrastructure code

Pretty cool, right?

---

## What's Next?

Want to take this further? Here are some ideas:

1. Add IPv6 support (because the future is now)
2. Build a web UI to manage everything visually
3. Add bandwidth monitoring per subnet
4. Implement route tables for more complex routing
5. Create Network ACLs for subnet-level security
6. Build a "multi-region" setup with multiple host machines

---

## Wrapping Up

So there you have it—you just built a VPC from scratch using nothing but Linux! You now understand how cloud providers create isolated networks, how NAT works, how routing decisions are made, and how to secure everything with firewalls.

The cool thing is, these concepts apply everywhere. Whether you're working with AWS, Azure, GCP, or even just setting up networks in your homelab, you now understand the fundamentals.

Hope you had as much fun building this as I did! If you get stuck or want to share what you built, drop a comment below.

Happy networking! 🚀

---

*Built this as part of the HNG Internship Stage 4 Task. Want to learn more cool stuff? Check out [HNG Internship](https://hng.tech/internship)!*