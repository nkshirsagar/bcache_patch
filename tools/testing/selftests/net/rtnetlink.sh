#!/bin/bash
#
# This test is for checking rtnetlink callpaths, and get as much coverage as possible.
#
# set -e

devdummy="test-dummy0"

# Kselftest framework requirement - SKIP code is 4.
ksft_skip=4

# set global exit status, but never reset nonzero one.
check_err()
{
	if [ $ret -eq 0 ]; then
		ret=$1
	fi
}

# same but inverted -- used when command must fail for test to pass
check_fail()
{
	if [ $1 -eq 0 ]; then
		ret=1
	fi
}

kci_add_dummy()
{
	ip link add name "$devdummy" type dummy
	check_err $?
	ip link set "$devdummy" up
	check_err $?
}

kci_del_dummy()
{
	ip link del dev "$devdummy"
	check_err $?
}

kci_test_netconf()
{
	dev="$1"
	r=$ret

	ip netconf show dev "$dev" > /dev/null
	check_err $?

	for f in 4 6; do
		ip -$f netconf show dev "$dev" > /dev/null
		check_err $?
	done

	if [ $ret -ne 0 ] ;then
		echo "FAIL: ip netconf show $dev"
		test $r -eq 0 && ret=0
		return 1
	fi
}

# add a bridge with vlans on top
kci_test_bridge()
{
	devbr="test-br0"
	vlandev="testbr-vlan1"

	local ret=0
	ip link add name "$devbr" type bridge
	check_err $?

	ip link set dev "$devdummy" master "$devbr"
	check_err $?

	ip link set "$devbr" up
	check_err $?

	ip link add link "$devbr" name "$vlandev" type vlan id 1
	check_err $?
	ip addr add dev "$vlandev" 10.200.7.23/30
	check_err $?
	ip -6 addr add dev "$vlandev" dead:42::1234/64
	check_err $?
	ip -d link > /dev/null
	check_err $?
	ip r s t all > /dev/null
	check_err $?

	for name in "$devbr" "$vlandev" "$devdummy" ; do
		kci_test_netconf "$name"
	done

	ip -6 addr del dev "$vlandev" dead:42::1234/64
	check_err $?

	ip link del dev "$vlandev"
	check_err $?
	ip link del dev "$devbr"
	check_err $?

	if [ $ret -ne 0 ];then
		echo "FAIL: bridge setup"
		return 1
	fi
	echo "PASS: bridge setup"

}

kci_test_gre()
{
	gredev=neta
	rem=10.42.42.1
	loc=10.0.0.1

	local ret=0
	ip tunnel add $gredev mode gre remote $rem local $loc ttl 1
	check_err $?
	ip link set $gredev up
	check_err $?
	ip addr add 10.23.7.10 dev $gredev
	check_err $?
	ip route add 10.23.8.0/30 dev $gredev
	check_err $?
	ip addr add dev "$devdummy" 10.23.7.11/24
	check_err $?
	ip link > /dev/null
	check_err $?
	ip addr > /dev/null
	check_err $?

	kci_test_netconf "$gredev"

	ip addr del dev "$devdummy" 10.23.7.11/24
	check_err $?

	ip link del $gredev
	check_err $?

	if [ $ret -ne 0 ];then
		echo "FAIL: gre tunnel endpoint"
		return 1
	fi
	echo "PASS: gre tunnel endpoint"
}

# tc uses rtnetlink too, for full tc testing
# please see tools/testing/selftests/tc-testing.
kci_test_tc()
{
	dev=lo
	local ret=0

	tc qdisc add dev "$dev" root handle 1: htb
	check_err $?
	tc class add dev "$dev" parent 1: classid 1:10 htb rate 1mbit
	check_err $?
	tc filter add dev "$dev" parent 1:0 prio 5 handle ffe: protocol ip u32 divisor 256
	check_err $?
	tc filter add dev "$dev" parent 1:0 prio 5 handle ffd: protocol ip u32 divisor 256
	check_err $?
	tc filter add dev "$dev" parent 1:0 prio 5 handle ffc: protocol ip u32 divisor 256
	check_err $?
	tc filter add dev "$dev" protocol ip parent 1: prio 5 handle ffe:2:3 u32 ht ffe:2: match ip src 10.0.0.3 flowid 1:10
	check_err $?
	tc filter add dev "$dev" protocol ip parent 1: prio 5 handle ffe:2:2 u32 ht ffe:2: match ip src 10.0.0.2 flowid 1:10
	check_err $?
	tc filter show dev "$dev" parent  1:0 > /dev/null
	check_err $?
	tc filter del dev "$dev" protocol ip parent 1: prio 5 handle ffe:2:3 u32
	check_err $?
	tc filter show dev "$dev" parent  1:0 > /dev/null
	check_err $?
	tc qdisc del dev "$dev" root handle 1: htb
	check_err $?

	if [ $ret -ne 0 ];then
		echo "FAIL: tc htb hierarchy"
		return 1
	fi
	echo "PASS: tc htb hierarchy"

}

kci_test_polrouting()
{
	local ret=0
	ip rule add fwmark 1 lookup 100
	check_err $?
	ip route add local 0.0.0.0/0 dev lo table 100
	check_err $?
	ip r s t all > /dev/null
	check_err $?
	ip rule del fwmark 1 lookup 100
	check_err $?
	ip route del local 0.0.0.0/0 dev lo table 100
	check_err $?

	if [ $ret -ne 0 ];then
		echo "FAIL: policy route test"
		return 1
	fi
	echo "PASS: policy routing"
}

kci_test_route_get()
{
	local ret=0

	ip route get 127.0.0.1 > /dev/null
	check_err $?
	ip route get 127.0.0.1 dev "$devdummy" > /dev/null
	check_err $?
	ip route get ::1 > /dev/null
	check_err $?
	ip route get fe80::1 dev "$devdummy" > /dev/null
	check_err $?
	ip route get 127.0.0.1 from 127.0.0.1 oif lo tos 0x1 mark 0x1 > /dev/null
	check_err $?
	ip route get ::1 from ::1 iif lo oif lo tos 0x1 mark 0x1 > /dev/null
	check_err $?
	ip addr add dev "$devdummy" 10.23.7.11/24
	check_err $?
	ip route get 10.23.7.11 from 10.23.7.12 iif "$devdummy" > /dev/null
	check_err $?
	ip addr del dev "$devdummy" 10.23.7.11/24
	check_err $?

	if [ $ret -ne 0 ];then
		echo "FAIL: route get"
		return 1
	fi

	echo "PASS: route get"
}

kci_test_addrlft()
{
	for i in $(seq 10 100) ;do
		lft=$(((RANDOM%3) + 1))
		ip addr add 10.23.11.$i/32 dev "$devdummy" preferred_lft $lft valid_lft $((lft+1))
		check_err $?
	done

	sleep 5

	ip addr show dev "$devdummy" | grep "10.23.11."
	if [ $? -eq 0 ]; then
		echo "FAIL: preferred_lft addresses remaining"
		check_err 1
		return
	fi

	echo "PASS: preferred_lft addresses have expired"
}

kci_test_addrlabel()
{
	local ret=0

	ip addrlabel add prefix dead::/64 dev lo label 1
	check_err $?

	ip addrlabel list |grep -q "prefix dead::/64 dev lo label 1"
	check_err $?

	ip addrlabel del prefix dead::/64 dev lo label 1 2> /dev/null
	check_err $?

	ip addrlabel add prefix dead::/64 label 1 2> /dev/null
	check_err $?

	ip addrlabel del prefix dead::/64 label 1 2> /dev/null
	check_err $?

	# concurrent add/delete
	for i in $(seq 1 1000); do
		ip addrlabel add prefix 1c3::/64 label 12345 2>/dev/null
	done &

	for i in $(seq 1 1000); do
		ip addrlabel del prefix 1c3::/64 label 12345 2>/dev/null
	done

	wait

	ip addrlabel del prefix 1c3::/64 label 12345 2>/dev/null

	if [ $ret -ne 0 ];then
		echo "FAIL: ipv6 addrlabel"
		return 1
	fi

	echo "PASS: ipv6 addrlabel"
}

kci_test_ifalias()
{
	local ret=0
	namewant=$(uuidgen)
	syspathname="/sys/class/net/$devdummy/ifalias"

	ip link set dev "$devdummy" alias "$namewant"
	check_err $?

	if [ $ret -ne 0 ]; then
		echo "FAIL: cannot set interface alias of $devdummy to $namewant"
		return 1
	fi

	ip link show "$devdummy" | grep -q "alias $namewant"
	check_err $?

	if [ -r "$syspathname" ] ; then
		read namehave < "$syspathname"
		if [ "$namewant" != "$namehave" ]; then
			echo "FAIL: did set ifalias $namewant but got $namehave"
			return 1
		fi

		namewant=$(uuidgen)
		echo "$namewant" > "$syspathname"
	        ip link show "$devdummy" | grep -q "alias $namewant"
		check_err $?

		# sysfs interface allows to delete alias again
		echo "" > "$syspathname"

	        ip link show "$devdummy" | grep -q "alias $namewant"
		check_fail $?

		for i in $(seq 1 100); do
			uuidgen > "$syspathname" &
		done

		wait

		# re-add the alias -- kernel should free mem when dummy dev is removed
		ip link set dev "$devdummy" alias "$namewant"
		check_err $?
	fi

	if [ $ret -ne 0 ]; then
		echo "FAIL: set interface alias $devdummy to $namewant"
		return 1
	fi

	echo "PASS: set ifalias $namewant for $devdummy"
}

kci_test_vrf()
{
	vrfname="test-vrf"
	local ret=0

	ip link show type vrf 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "SKIP: vrf: iproute2 too old"
		return $ksft_skip
	fi

	ip link add "$vrfname" type vrf table 10
	check_err $?
	if [ $ret -ne 0 ];then
		echo "FAIL: can't add vrf interface, skipping test"
		return 0
	fi

	ip -br link show type vrf | grep -q "$vrfname"
	check_err $?
	if [ $ret -ne 0 ];then
		echo "FAIL: created vrf device not found"
		return 1
	fi

	ip link set dev "$vrfname" up
	check_err $?

	ip link set dev "$devdummy" master "$vrfname"
	check_err $?
	ip link del dev "$vrfname"
	check_err $?

	if [ $ret -ne 0 ];then
		echo "FAIL: vrf"
		return 1
	fi

	echo "PASS: vrf"
}

kci_test_encap_vxlan()
{
	local ret=0
	vxlan="test-vxlan0"
	vlan="test-vlan0"
	testns="$1"

	ip netns exec "$testns" ip link add "$vxlan" type vxlan id 42 group 239.1.1.1 \
		dev "$devdummy" dstport 4789 2>/dev/null
	if [ $? -ne 0 ]; then
		echo "FAIL: can't add vxlan interface, skipping test"
		return 0
	fi
	check_err $?

	ip netns exec "$testns" ip addr add 10.2.11.49/24 dev "$vxlan"
	check_err $?

	ip netns exec "$testns" ip link set up dev "$vxlan"
	check_err $?

	ip netns exec "$testns" ip link add link "$vxlan" name "$vlan" type vlan id 1
	check_err $?

	ip netns exec "$testns" ip link del "$vxlan"
	check_err $?

	if [ $ret -ne 0 ]; then
		echo "FAIL: vxlan"
		return 1
	fi
	echo "PASS: vxlan"
}

kci_test_encap_fou()
{
	local ret=0
	name="test-fou"
	testns="$1"

	ip fou help 2>&1 |grep -q 'Usage: ip fou'
	if [ $? -ne 0 ];then
		echo "SKIP: fou: iproute2 too old"
		return $ksft_skip
	fi

	if ! /sbin/modprobe -q -n fou; then
		echo "SKIP: module fou is not found"
		return $ksft_skip
	fi
	/sbin/modprobe -q fou
	ip netns exec "$testns" ip fou add port 7777 ipproto 47 2>/dev/null
	if [ $? -ne 0 ];then
		echo "FAIL: can't add fou port 7777, skipping test"
		return 1
	fi

	ip netns exec "$testns" ip fou add port 8888 ipproto 4
	check_err $?

	ip netns exec "$testns" ip fou del port 9999 2>/dev/null
	check_fail $?

	ip netns exec "$testns" ip fou del port 7777
	check_err $?

	if [ $ret -ne 0 ]; then
		echo "FAIL: fou"
		return 1
	fi

	echo "PASS: fou"
}

# test various encap methods, use netns to avoid unwanted interference
kci_test_encap()
{
	testns="testns"
	local ret=0

	ip netns add "$testns"
	if [ $? -ne 0 ]; then
		echo "SKIP encap tests: cannot add net namespace $testns"
		return $ksft_skip
	fi

	ip netns exec "$testns" ip link set lo up
	check_err $?

	ip netns exec "$testns" ip link add name "$devdummy" type dummy
	check_err $?
	ip netns exec "$testns" ip link set "$devdummy" up
	check_err $?

	kci_test_encap_vxlan "$testns"
	check_err $?
	kci_test_encap_fou "$testns"
	check_err $?

	ip netns del "$testns"
	return $ret
}

kci_test_macsec()
{
	msname="test_macsec0"
	local ret=0

	ip macsec help 2>&1 | grep -q "^Usage: ip macsec"
	if [ $? -ne 0 ]; then
		echo "SKIP: macsec: iproute2 too old"
		return $ksft_skip
	fi

	ip link add link "$devdummy" "$msname" type macsec port 42 encrypt on
	check_err $?
	if [ $ret -ne 0 ];then
		echo "FAIL: can't add macsec interface, skipping test"
		return 1
	fi

	ip macsec add "$msname" tx sa 0 pn 1024 on key 01 12345678901234567890123456789012
	check_err $?

	ip macsec add "$msname" rx port 1234 address "1c:ed:de:ad:be:ef"
	check_err $?

	ip macsec add "$msname" rx port 1234 address "1c:ed:de:ad:be:ef" sa 0 pn 1 on key 00 0123456789abcdef0123456789abcdef
	check_err $?

	ip macsec show > /dev/null
	check_err $?

	ip link del dev "$msname"
	check_err $?

	if [ $ret -ne 0 ];then
		echo "FAIL: macsec"
		return 1
	fi

	echo "PASS: macsec"
}

kci_test_rtnl()
{
	local ret=0
	kci_add_dummy
	if [ $ret -ne 0 ];then
		echo "FAIL: cannot add dummy interface"
		return 1
	fi

	kci_test_polrouting
	check_err $?
	kci_test_route_get
	check_err $?
	kci_test_addrlft
	check_err $?
	kci_test_tc
	check_err $?
	kci_test_gre
	check_err $?
	kci_test_bridge
	check_err $?
	kci_test_addrlabel
	check_err $?
	kci_test_ifalias
	check_err $?
	kci_test_vrf
	check_err $?
	kci_test_encap
	check_err $?
	kci_test_macsec
	check_err $?

	kci_del_dummy
	return $ret
}

#check for needed privileges
if [ "$(id -u)" -ne 0 ];then
	echo "SKIP: Need root privileges"
	exit $ksft_skip
fi

for x in ip tc;do
	$x -Version 2>/dev/null >/dev/null
	if [ $? -ne 0 ];then
		echo "SKIP: Could not run test without the $x tool"
		exit $ksft_skip
	fi
done

kci_test_rtnl

exit $?
