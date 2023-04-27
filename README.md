# TFGEN (Script to generate libvirt instance configuration for Terraform)

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html)
- [Terraform Libvirt Provider](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs)

## Installing Dependencies

### Terraform Libvirt Provider

Terraform libvirt provider binaries prebuilt include in this repository. The version of the provider is 0.7.1.

```bash
# Clone repo
git clone https://github.com/Script47ph/terraform-kvm-script.git && cd terraform-kvm-script

# Create libvirt provider directory
mkdir -p ~/.local/share/terraform/plugins/registry.terraform.io/dmacvicar/libvirt/0.7.1/linux_amd64

# Move libvirt provider binaries to the directory
mv libvirt-provider/terraform-provider-libvirt ~/.local/share/terraform/plugins/registry.terraform.io/dmacvicar/libvirt/0.7.1/linux_amd64

# Add execute permission
chmod +x ~/.local/share/terraform/plugins/registry.terraform.io/dmacvicar/libvirt/0.7.1/linux_amd64/terraform-provider-libvirt
```

### New feature:
* Interface without IP Address
```txt
[VMn]
IFACE_NETWORK2: 10.10.20.0
IFACE_IP2: none
```

### Core
- [x] Create main HCL file (main.tf)
  - [x] Nested Guest
  - [x] Graphics: VNC or Spice
  - [x] Dynamic multi disk drives
- [x] Create Cloudinit
  - [x] User: student & instructor
- [x] Create Network Config
  - [x] Dynamic multi interface

### TFGEN Guide

For example you want to create 2 VM(s) with following specification:

| VM Name     | OS                    | vCPU(s) | Nested | RAM | Storage                         | NIC                                            | Console | Inject Public Key |
| ----------- | --------------------- | ------- | ------ | --- | ------------------------------- | ---------------------------------------------- | ------- | ----------------- |
| demo-tfgen1 | template-focal.img    | 2       | N      | 4G  | vda: 10G<br>vdb: 10G<br>vdc: 5G | ens3: 10.10.110.10/24                          | spice   | root@example      |
| demo-tfgen2 | template-rocky9.qcow2 | 2       | Y      | 4G  | vda: 50G                        | eth0: 10.10.110.20/24<br>eth1: 10.10.120.20/24 | vnc     | root@example      |

You will need to create environment file like following example:

```sh
vim demo-env.txt
```

```txt
[LAB]
PUBKEY1: ssh-rsa example root@example

[VM1]
NAME: demo-tfgen1
OS: template-focal.img
NESTED: N
VCPUS: 2
MEMORY: 4G
DISK1: 10G
DISK2: 10G
DISK3: 5G
IFACE_NETWORK1: 10.10.110.0
IFACE_IP1: 10.10.110.10
CONSOLE: spice

[VM2]
NAME: demo-tfgen2
OS: template-rocky9.qcow2
NESTED: Y
VCPUS: 4
MEMORY: 4G
DISK1: 50G
IFACE_NETWORK1: 10.10.110.0
IFACE_IP1: 10.10.110.20
IFACE_NETWORK2: 10.10.120.0
IFACE_IP2: 10.10.120.20
CONSOLE: vnc
```

Generate Terraform files based on your environment file

```bash
# not-tfgen.sh <new_tf_dir> <env_file>
tfgen.sh demo-dir demo-env.txt
```

Now you are ready to create the VM

```bash
cd demo-dir

terraform init

terraform apply -auto-approve
```

### Explanation
Note: Only works on btech lab

#### [LAB] Section
- PUBKEYn: Public Key that will be injected to the VM

#### [VMn] Section
- NAME: domain name shown in virsh list
- OS: Cloud image name on pool storage (virsh vol-list isos)
- NESTED: y | n . Enable nested
- VCPUS: vCPU(s)
- MEMORY: nG. n is integer, only support Gigabyte Unit
- DISKn: nG. n is integer, only support Gigabyte Unit
- IFACE_NETWORKn: Network Address used by guest
- IFACE_IPn: IP Address used by guest
- CONSOLE: spice | vnc. Select console

## [Bonus] Deploy from scatch

### Create Storage Pool

**Pool for cloud image**

```bash
# Create pool directory
mkdir -p ~/data/isos/

# Create pool
virsh pool-define-as --name isos --type dir --target ~/data/isos/

# Start pool
virsh pool-start isos

# Autostart pool
virsh pool-autostart isos

# Verify pool
virsh pool-list --all
virsh pool-info isos
```

**Pool for VM disk**

```bash
# Create pool directory
mkdir -p ~/data/vms/

# Create pool
virsh pool-define-as --name vms --type dir --target ~/data/vms/

# Start pool
virsh pool-start vms

# Autostart pool
virsh pool-autostart vms

# Verify pool
virsh pool-list --all
virsh pool-info vms
```

### [Ubuntu Only] Add storage pool directory to Apparmor

```bash
sudo vim /etc/apparmor.d/libvirt/TEMPLATE.qemu
```
```vim
# Add the following line to section "profile LIBVIRT_TEMPLATE flags=(attach_disconnected)"
~/data/vms/ rwk,
~/data/isos/ rwk,
```


### Create Cloud Image

```bash
# Download cloud image
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img -O ~/data/isos/template-focal.img

# Refresh pool
virsh pool-refresh isos
```

### Create Network

```bash
# Create network configuration file
vim net-10.10.13.xml
```

```xml
<network>
  <name>net-10.10.13</name>
  <forward mode='nat'/>
  <bridge name='br-10.10.13' stp='on' delay='0'/>
  <ip address='10.10.13.1' netmask='255.255.255.0'>
    <dhcp>
        <range start='10.10.13.1' end='10.10.13.250'/>
    </dhcp>
  </ip>
</network>
```

```bash
# Apply network configuration
virsh net-define net-10.10.13.xml

# Start network
virsh net-start net-10.10.13

# Autostart network
virsh net-autostart net-10.10.13

# Verify network
virsh net-list --all
virsh net-info net-10.10.13
```

### Create VM

```bash
# Create VM configuration file
vim vm-demo.txt
```

```txt
[LAB1]
PUBKEY1: YOUR_PUBKEY

[VM1]
NAME: demo
OS: template-focal.img
NESTED: Y
VCPUS: 2
MEMORY: 4G
DISK1: 10G
IFACE_NETWORK1: 10.10.13.0
IFACE_IP1: 10.10.13.13
CONSOLE: vnc
```

```bash
# Generate Terraform files
chmod +x tfgen.sh
./tfgen.sh demo-dir vm-demo.txt

# Terraform init
cd demo-dir
terraform init

# Terraform apply
terraform apply -auto-approve
```

### Check VM

```bash
virsh list --all
virsh console demo
```
