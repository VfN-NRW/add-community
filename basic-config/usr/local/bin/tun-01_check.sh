#!/bin/bash
INTERFACE=tun-vpn-01
INTERFACE2=eth0
STOP_GW=0

shopt -s nullglob

ping -q -I $INTERFACE 8.8.8.8 -c 4 -i 1 -W 5 >/dev/null 2>&1

if test $? -eq 0; then
    NEW_STATE=server
else
    NEW_STATE=off
fi

if [ -f /tmp/stop_gateway ]; then
    logger "Stop-Gateway-marker shutting down dhcpd and batman-server-mode..."
    NEW_STATE=off
    STOP_GW=1
    mv /tmp/stop_gateway /tmp/gateway_stopped
else
    if [ -f /tmp/gateway_stopped ]; then
        if [ "$NEW_STATE" == "off" ]; then
            logger "Gateway is stopped, uplink is dead, remove /tmp/gateway_stopped to reactivate automatic..."
        else
            logger "Gateway is stopped, uplink is working, remove /tmp/gateway_stopped to reactivate automatic..."
        fi
        NEW_STATE=off
        STOP_GW=2
    fi  
fi

#try to restart tun-01 automatically
if [ "$NEW_STATE" == "off" -a "$STOP_GW" -eq 0 ]; then
    logger "try a restart of openvpn via systemctl"
    systemctl restart openvpn@tun-01
    echo "1" >> /tmp/tun-vpn-01_check.restart
    chmod 777 /tmp/tun-vpn-01_check.restart
    chown munin:users /tmp/tun-vpn-01_check.restart
fi

#get current traffic on interfaces

rxold=`cat /tmp/tun-vpn-01_check.rx_bytes`
rxold=${rxold:-0}
txold=`cat /tmp/tun-vpn-01_check.tx_bytes`
txold=${txold:-0}
rxnew=`cat /sys/class/net/$INTERFACE2/statistics/rx_bytes`
txnew=`cat /sys/class/net/$INTERFACE2/statistics/tx_bytes`

rx=$(expr $rxnew - $rxold)
tx=$(expr $txnew - $txold)

#fix wrong values after reboot
if [ $rx -lt 0 ]; then
	$rx=0
fi
if [ $tx -lt 0 ]; then
	$tx=0
fi

rx=$(expr $rx \* 8) #byte to bit
rx=$(expr $rx / 1000) #k
rx=$(expr $rx / 1000) #m
rx=$(expr $rx / 60) #sec
tx=$(expr $tx \* 8) #byte to bit
tx=$(expr $tx / 1000) #k
tx=$(expr $tx / 1000) #m
tx=$(expr $tx / 60) #sec
logger "Detected network load tx: $tx Mbit/s rx: $rx Mbit/s"

#if there are to high values detected

if [ $rx -gt 99 ]; then
	rx=99
fi
if [ $tx -gt 99 ]; then
	tx=99
fi

#get remainig bandwith
rx=$(expr 85 - $rx)
tx=$(expr 85 - $tx)

#if lower than 1 Mbit set to 1 Mbit
# else we would set batman to default values
if [ $rx -lt 1 ]; then
	rx=1
fi
if [ $tx -lt 1 ]; then
	tx=1
fi

#use highest value
if [ $rx -gt $tx ]; then
	bw=$rx
else
	bw=$tx
fi

#save new values
echo "$rxnew" > /tmp/tun-vpn-01_check.rx_bytes
echo "$txnew" > /tmp/tun-vpn-01_check.tx_bytes

#mesh definitions
meshdevs=()
#=+#

firstdev=1

for MESH in $meshdevs; do
  #start / stop dhcpd
  if [ $firstdev -eq 1 ]; then
    OLD_STATE="$(cat /sys/class/net/$MESH/mesh/gw_mode)"
    if [ ! "$OLD_STATE" == "$NEW_STATE" ]; then
  
      if [ "$NEW_STATE" == "off" ]; then
        logger "shutting down dhcpd..."
        systemctl stop dhcpd4
      elif [ "$NEW_STATE" == "server" ]; then
        logger "starting dhcpd..."
        systemctl start dhcpd4
      fi
    fi
  fi
  
  if [ -f /sys/class/net/$MESH/mesh/gw_mode ]; then
    OLD_STATE="$(cat /sys/class/net/$MESH/mesh/gw_mode)"
    if [ ! "$OLD_STATE" == "$NEW_STATE" ]; then 
      echo $NEW_STATE > /sys/class/net/$MESH/mesh/gw_mode
      logger "$MESH: batman gateway mode changed to $NEW_STATE"
    fi
    echo ${bw}MBit/${bw}MBit > /sys/class/net/$MESH/mesh/gw_bandwidth
  fi
  
done

