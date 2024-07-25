generate_template() {
  mkdir -p ${TMP_DIR}
  cat <<'EOF' >${TMP_DIR}/${HCL_FILE}
provider "libvirt" {
    uri = "qemu:///system"
}

terraform {
 required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
  }
}
    
EOF
  source function/variable.sh
  pod_info
  END=$(cat ${ENV_FILE} | awk -F '[][]' '{print $2}' | grep VM | wc -l)
  for ((i = 1; i <= END; i++)); do
    VM_NAME=VM${i}_NAME
    cat <<EOF >>${TMP_DIR}/${HCL_FILE}
resource "libvirt_cloudinit_disk" "${!VM_NAME}-cloudinit" {
    name = "${!VM_NAME}-cloudinit.iso"
    pool = "vms"
    user_data = data.template_file.user${i}_data.rendered
    network_config = data.template_file.network${i}_config.rendered
}
    
data "template_file" "user${i}_data" {
    template = file("\${path.module}/cloudinit${i}.cfg")
}
    
data "template_file" "network${i}_config" {
    template = file("\${path.module}/network${i}_config.cfg")
}

EOF
    VM_DISK1=VM${i}_DISK1
    VM_OS=VM${i}_OS
    cat <<EOF >>${TMP_DIR}/${HCL_FILE}
resource "libvirt_volume" "${!VM_NAME}-vda" {
    name = "${!VM_NAME}-vda.qcow2"
    pool = "vms"
    base_volume_name = "${!VM_OS}"
    base_volume_pool = "isos"
    size = "${!VM_DISK1}"
    format = "qcow2"
}

EOF
    ALPINC=({a..z})
    y=2
    TOTAL_DISK=$(($(awk "/VM${i}/" RS= ${ENV_FILE} | grep DISK | wc -l) - 1))
    for ((x = 0; x < TOTAL_DISK; x++)); do
      export VM_DISK${y}=VM${i}_DISK${y}
      cat <<EOF >>${TMP_DIR}/${HCL_FILE}
resource "libvirt_volume" "${!VM_NAME}-vd${ALPINC[x + 1]}" {
    name = "${!VM_NAME}-vd${ALPINC[x + 1]}.qcow2"
    pool = "vms"
    size = "$(eval echo \${!VM_DISK${y}})"
    format = "qcow2"
}

EOF
      ((y++))
    done

    VM_MEMORY=VM${i}_MEMORY
    VM_VCPUS=VM${i}_VCPUS
    cat <<EOF >>${TMP_DIR}/${HCL_FILE}
resource "libvirt_domain" "${!VM_NAME}" {
    name = "${!VM_NAME}"
    memory = "${!VM_MEMORY}"
    vcpu = "${!VM_VCPUS}"
    # machine = "pc-i440fx-6.2"

EOF
    if [[ $(eval echo $(echo '$'\{VM${i}_NESTED\})) != Y ]]; then
      cat <<EOF >>${TMP_DIR}/${HCL_FILE}
    cpu {
           mode = ""
    }

EOF
    else
      cat <<EOF >>${TMP_DIR}/${HCL_FILE}
    cpu {
           mode = "host-passthrough"
    }

EOF
    fi

    cat <<EOF >>${TMP_DIR}/${HCL_FILE}
    cloudinit = libvirt_cloudinit_disk.${!VM_NAME}-cloudinit.id

    console {
        type        = "pty"
        target_port = "0"
        target_type = "serial"
    }

    console {
        type        = "pty"
        target_port = "1"
        target_type = "virtio"
    }

EOF
    y=1
    TOTAL_IFACE=$(awk "/VM${i}/" RS= ${ENV_FILE} | grep IFACE_NETWORK | wc -l)
    for ((x = 0; x < TOTAL_IFACE; x++)); do
      export VM_IFACE_NETWORK${y}=VM${i}_IFACE_NETWORK${y}
      export VM_IFACE_IP${y}=VM${i}_IFACE_IP${y}
      if [[ $(eval echo \${!VM_IFACE_IP${y}}) == "none" ]]; then
        cat <<EOF >>${TMP_DIR}/${HCL_FILE}
    network_interface {
        network_name = "net-$(eval echo \${!VM_IFACE_NETWORK${y}} | cut -d '.' -f-3)"
    }

EOF
        ((y++))
      else
        cat <<EOF >>${TMP_DIR}/${HCL_FILE}
    network_interface {
        network_name = "net-$(eval echo \${!VM_IFACE_NETWORK${y}} | cut -d '.' -f-3)"
        addresses = ["$(eval echo \${!VM_IFACE_IP${y}})"]
    }

EOF
        ((y++))
      fi
    done

    ALPINC=({a..z})
    TOTAL_DISK=$(awk "/VM${i}/" RS= ${ENV_FILE} | grep DISK | wc -l)
    for ((x = 0; x < TOTAL_DISK; x++)); do
      export VM_DISK${y}=VM${i}_DISK${y}
      cat <<EOF >>${TMP_DIR}/${HCL_FILE}
    disk {
        volume_id = libvirt_volume.${!VM_NAME}-vd${ALPINC[x]}.id
    }

EOF
    done

    VM_CONSOLE=VM${i}_CONSOLE
    cat <<EOF >>${TMP_DIR}/${HCL_FILE}
    video {
        type = "vga"
    }
    
    graphics {
        type = "${!VM_CONSOLE}"
        listen_type = "address"
        autoport = true
    }
}

EOF
    TOTAL_KEY=$(awk "/LAB/" RS= ${ENV_FILE} | grep PUBKEY | wc -l)
    if [[ ${!VM_OS} = $(echo ${!VM_OS} | egrep -i -h "centos|redhat|rocky|alma") ]]; then
      if grep -q LAB ${ENV_FILE}; then
        cat <<EOF >${TMP_DIR}/cloudinit${i}.cfg
#cloud-config
hostname: ${!VM_NAME}
local-hostname: ${!VM_NAME}
fqdn: ${!VM_NAME}.localdomain
users:
  - name: root
    ssh_authorized_keys:
EOF
        for ((x = 1; x <= TOTAL_KEY; x++)); do
          cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
      - $(eval echo \${PUBKEY${x}})
EOF
        done
        cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
  - name: instructor
    ssh_authorized_keys:
EOF
        for ((x = 1; x <= TOTAL_KEY; x++)); do
          cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
      - $(eval echo \${PUBKEY${x}})
EOF
        done
        cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: users, wheel
  - name: student
    ssh_authorized_keys:
EOF
        for ((x = 1; x <= TOTAL_KEY; x++)); do
          PUB_KEY=PUBKEY${x}
          cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
      - $(eval echo \${PUBKEY${x}})
EOF
        done
        cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: users, wheel
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
     student:SEDhZthtQdbo/+7TfYc5KvfGduWg/VjOto5oFDdfCCY=
  expire: false

runcmd:
  - dnf repolist
  - dnf install -y epel-release
  - dnf install -y qemu-guest-agent neofetch
  - systemctl enable --now qemu-guest-agent.service
  - |
    echo "" >> /etc/hosts
    echo "########## Generate from cloudinit ##########" >> /etc/hosts
    echo "\$(hostname -I | awk '{print \$1}') ${!VM_NAME}" >> /etc/hosts
EOF
      else
        cat <<EOF >${TMP_DIR}/cloudinit${i}.cfg
#cloud-config
hostname: ${!VM_NAME}
local-hostname: ${!VM_NAME}
fqdn: ${!VM_NAME}.localdomain
users:
  - name: instructor
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: users, wheel
  - name: student
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: users, wheel
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
     student:SEDhZthtQdbo/+7TfYc5KvfGduWg/VjOto5oFDdfCCY=
  expire: false

package_update: true
packages:
  - qemu-guest-agent
  - neofetch

runcmd:
  - systemctl enable --now qemu-guest-agent.service
  - |
    echo "" >> /etc/hosts
    echo "########## Generate from cloudinit ##########" >> /etc/hosts
    echo "\$(hostname -I | awk '{print \$1}') ${!VM_NAME}" >> /etc/hosts
EOF
      fi

      y=1
      TOTAL_IFACE=$(awk "/VM${i}/" RS= ${ENV_FILE} | grep IFACE_NETWORK | wc -l)
      for ((x = 0; x < TOTAL_IFACE; x++)); do
        cat <<EOF >${TMP_DIR}/network${i}_config.cfg
version: 1
config:
  - type: physical
    name: eth0
    subnets:
      - type: static
        address: $(eval echo \${!VM_IFACE_IP${y}})
        netmask: 255.255.255.0  
        gateway: $(eval echo \${!VM_IFACE_IP${y}} | cut -d '.' -f-3).1
        dns_nameservers:
          - 1.1.1.1
        routes:
            - network: 0.0.0.0
              netmask: 0.0.0.0
              gateway: $(eval echo \${!VM_IFACE_IP${y}} | cut -d '.' -f-3).1
EOF
        ((y++))
        if [[ $(awk "/VM${i}/" RS= ${ENV_FILE} | grep IFACE_NETWORK | wc -l) -ge 1 ]]; then
          for ((x = 1; x < TOTAL_IFACE; x++)); do
            if [[ $(eval echo \${!VM_IFACE_IP${y}}) == "none" ]]; then
              cat <<EOF >>${TMP_DIR}/network${i}_config.cfg
  - type: physical
    name: eth${x}
EOF
              ((y++))
            else
              cat <<EOF >>${TMP_DIR}/network${i}_config.cfg
  - type: physical
    name: eth${x}
    subnets:
      - type: static
        address: $(eval echo \${!VM_IFACE_IP${y}})
        netmask: 255.255.255.0  
        gateway: $(eval echo \${!VM_IFACE_IP${y}} | cut -d '.' -f-3).1
EOF
              ((y++))
            fi
          done
        fi
      done
    fi
    if [[ ${!VM_OS} = $(echo ${!VM_OS} | egrep -i -h "ubuntu|trusty|xenial|bionic|focal|jammy|debian|bookworm|buster|bullseye") ]]; then
      if grep -q LAB ${ENV_FILE}; then
        cat <<EOF >${TMP_DIR}/cloudinit${i}.cfg
#cloud-config
hostname: ${!VM_NAME}
local-hostname: ${!VM_NAME}
fqdn: ${!VM_NAME}.localdomain
users:
  - name: root
    ssh_authorized_keys:
EOF
        for ((x = 1; x <= TOTAL_KEY; x++)); do
          cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
      - $(eval echo \${PUBKEY${x}})
EOF
        done
        cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
  - name: instructor
    ssh_authorized_keys:
EOF
        for ((x = 1; x <= TOTAL_KEY; x++)); do
          cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
      - $(eval echo \${PUBKEY${x}})
EOF
        done
        cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: users, admin
  - name: student
    ssh_authorized_keys:
EOF
        for ((x = 1; x <= TOTAL_KEY; x++)); do
          PUB_KEY=PUBKEY${x}
          cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
      - $(eval echo \${PUBKEY${x}})
EOF
        done
        cat <<EOF >>${TMP_DIR}/cloudinit${i}.cfg
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: users, admin
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
     student:SEDhZthtQdbo/+7TfYc5KvfGduWg/VjOto5oFDdfCCY=
  expire: false

package_update: true
packages:
  - qemu-guest-agent
  - neofetch

runcmd:
  - systemctl enable --now qemu-guest-agent.service
  - |
    echo "" >> /etc/hosts
    echo "########## Generate from cloudinit ##########" >> /etc/hosts
    echo "\$(hostname -I | awk '{print \$1}') ${!VM_NAME}" >> /etc/hosts
EOF
      else
        cat <<EOF >${TMP_DIR}/cloudinit${i}.cfg
#cloud-config
hostname: ${!VM_NAME}
local-hostname: ${!VM_NAME}
fqdn: ${!VM_NAME}.localdomain
users:
  - name: instructor
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: users, admin
  - name: student
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
    groups: users, admin
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
     student:SEDhZthtQdbo/+7TfYc5KvfGduWg/VjOto5oFDdfCCY=
  expire: false

package_update: true
packages:
  - qemu-guest-agent
  - neofetch

runcmd:
  - systemctl enable --now qemu-guest-agent.service
  - |
    echo "" >> /etc/hosts
    echo "########## Generate from cloudinit ##########" >> /etc/hosts
    echo "\$(hostname -I | awk '{print \$1}') ${!VM_NAME}" >> /etc/hosts
EOF
      fi

      y=1
      z=3
      TOTAL_IFACE=$(awk "/VM${i}/" RS= ${ENV_FILE} | grep IFACE_NETWORK | wc -l)
      for ((x = 0; x < TOTAL_IFACE; x++)); do
        cat <<EOF >${TMP_DIR}/network${i}_config.cfg
version: 2
ethernets:
  ens${z}:
    dhcp4: false
    addresses:
      - $(eval echo \${!VM_IFACE_IP${y}})/24
    gateway4: $(eval echo \${!VM_IFACE_IP${y}} | cut -d '.' -f-3).1
    nameservers:
      addresses: [1.1.1.1]
EOF
        ((y++))
        ((z++))
        if [[ $(awk "/VM${i}/" RS= ${ENV_FILE} | grep IFACE_NETWORK | wc -l) -ge 1 ]]; then
          for ((x = 1; x < TOTAL_IFACE; x++)); do
            if [[ $(eval echo \${!VM_IFACE_IP${y}}) == "none" ]]; then
              cat <<EOF >>${TMP_DIR}/network${i}_config.cfg
  ens${z}:
    dhcp4: false
EOF
              ((y++))
              ((z++))
            else
              cat <<EOF >>${TMP_DIR}/network${i}_config.cfg
  ens${z}:
    dhcp4: false
    addresses:
      - $(eval echo \${!VM_IFACE_IP${y}})/24
EOF
              ((y++))
              ((z++))
            fi
          done
        fi
      done
    fi
  done
  sed -i '${/^$/d}' ${TMP_DIR}/${HCL_FILE}
}
