#!/bin/sh
ip route replace 0.0.0.0/1 via $4 table 42
ip route replace 128.0.0.0/1 via $4 table 42
ifconfig tun-vpn-01 txqueuelen 10000
tc qdisc replace dev tun-vpn-01 root fq limit 10000 flow_limit 50 buckets 256 quantum 328 initial_quantum 15140
#tc qdisc replace dev tun-vpn-01 root fq_codel limit 10000 quantum 500 noecn
exit 0

