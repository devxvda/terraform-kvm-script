pod_info() {
    if grep -q LAB ${ENV_FILE}; then
        x=1
        for PUB_KEY in $(awk "/LAB/" RS= ${ENV_FILE} | grep PUBKEY | cut -d ':' -f 1); do
            export ${PUB_KEY}="$(awk "/LAB/" RS= ${ENV_FILE} | grep PUBKEY${x} | cut -d' ' -f 2-)"
            ((x++))
        done
    fi
    for DOMAIN_NAME in $(cat ${ENV_FILE} | grep VM | awk -F '[][]' '{print $2}'); do
        echo Rendering ${DOMAIN_NAME}
        export ${DOMAIN_NAME}_NAME=$(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep NAME | awk '{print $2}')
        #echo $(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep NAME | awk '{print $2}')
        export ${DOMAIN_NAME}_OS=$(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep OS | awk '{print $2}')
        export ${DOMAIN_NAME}_NESTED=$(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep NESTED | awk '{print $2}')
        export ${DOMAIN_NAME}_VCPUS=$(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep VCPUS | awk '{print $2}')
        export ${DOMAIN_NAME}_MEMORY=$(($(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep MEMORY | awk '{print $2}' | sed 's/[gG]$//') * 1024))
        for DISK_NAME in $(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep DISK | awk '{print $1}' | sed 's/.$//'); do
            export ${DOMAIN_NAME}_${DISK_NAME}=$(($(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep -w ${DISK_NAME} | awk '{print $2}' | sed 's/[gG]$//') * 1073741824))
        done
        for IFACE_NETWORK in $(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep IFACE_NETWORK | awk '{print $1}' | sed 's/.$//'); do
            export ${DOMAIN_NAME}_${IFACE_NETWORK}="$(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep -w ${IFACE_NETWORK} | awk '{print $2}')"
        done
        for IFACE_IP in $(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep IFACE_IP | awk '{print $1}' | sed 's/.$//'); do
            export ${DOMAIN_NAME}_${IFACE_IP}="$(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep -w ${IFACE_IP} | awk '{print $2}')"
        done
        export ${DOMAIN_NAME}_CONSOLE=$(awk "/\<${DOMAIN_NAME}\>/" RS= ${ENV_FILE} | grep CONSOLE | awk '{print $2}')
    done
}
