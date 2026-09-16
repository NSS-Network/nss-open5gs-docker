#!/bin/bash
set -eo pipefail

function tun_create {
    if ! grep "ogstun" /proc/net/dev > /dev/null; then
        echo "Creating ogstun device"
        ip tuntap add name ogstun mode tun
    fi
    ip addr del 10.45.0.1/16 dev ogstun 2> /dev/null || true
    ip addr add 10.45.0.1/16 dev ogstun
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
    ip addr del 2001:db8:cafe::1/48 dev ogstun 2> /dev/null || true
    ip addr add 2001:db8:cafe::1/48 dev ogstun
    ip link set ogstun up

    # For IMS
    if ! grep "ogstun2" /proc/net/dev > /dev/null; then
        echo "Creating ogstun2 device for IMS"
        ip tuntap add name ogstun2 mode tun
    fi
    ip addr del 10.46.0.1/16 dev ogstun2 2> /dev/null || true
    ip addr add 10.46.0.1/16 dev ogstun2
    ip addr del 2001:db8:cafe:1::1/48 dev ogstun2 2> /dev/null || true
    ip addr add 2001:db8:cafe:1::1/48 dev ogstun2
    ip link set ogstun2 up

    sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
    iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE || true
    iptables -t nat -A POSTROUTING -s 10.46.0.0/16 ! -o ogstun2 -j MASQUERADE || true
}

COMMAND=$1

if [[ "$COMMAND" == *"open5gs-upfd" ]]; then
    echo "Running tun_if script"
    tun_create
fi

$@
exit 1
