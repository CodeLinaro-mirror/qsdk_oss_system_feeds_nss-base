#!/bin/sh
#
# Copyright (c) 2023-2024, Qualcomm Innovation Center, Inc. All rights reserved.
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

# Initialize timeout counter
timeout_count=0

# Maximum recovery time
max_recovery_time=30

# Get board name
board=$(cat /tmp/sysinfo/board_name)

# Determine SoC type based on board name
if [[ "$board" == *"ipq9574"* ]]; then
	soc_type="alder"
elif [[ "$board" == *"ipq5332"* ]]; then
	soc_type="miami"
elif [[ "$board" == *"ipq5424"* ]]; then
        soc_type="marina"
elif [[ "$board" == *"ipq9650"* ]]; then
	soc_type="juhu"
elif [[ "$board" == *"ipq5210"* ]]; then
	soc_type="hermosa"
else
	echo "Error: Unsupported SoC type $board" > /var/log/edma_recovery.log
	exit 1
fi

# Check if log file exists
if [ -f /var/log/edma_recovery.log ]; then

	# Read current hang count from log file
	hang_count=$(grep "hang_count" /var/log/edma_recovery.log | cut -d':' -f2 | tr -d ' ')
else
	hang_count=0
fi

# Update hang count to maintain number of hangs happened
hang_count=$((hang_count + 1))

# Log current date and time
echo "date_time: $(date)" > /var/log/edma_recovery.log

# Log updated hang count
echo "hang_count: $hang_count" >> /var/log/edma_recovery.log

# Dump EDMA information to log file
edma_dump ${soc_type} general >> /var/log/edma_recovery.log

# rmmod_if_loaded()
#	Remove a kernel module only if it is currently loaded.
rmmod_if_loaded() {
	mod=$1
	if [ -d "/sys/module/${mod}" ]; then
		rmmod "${mod}"
	fi
}

# insmod_if_present()
#	Insert a kernel module only if the module file can be found.
#	Extra arguments are passed through to insmod (e.g. module params).
insmod_if_present() {
	mod=$1
	shift
	mod_path=$(find /lib/modules/$(uname -r) -name "${mod}.ko" 2>/dev/null | head -n 1)
	if [ -n "${mod_path}" ]; then
		insmod "${mod_path}" "$@"
	fi
}

/etc/init.d/network stop

rmmod_if_loaded qca_wifi_nss_plugins
rmmod_if_loaded ath12k_wifi8
rmmod_if_loaded ath12k_wifi7
rmmod_if_loaded ath12k

sleep 5

# Trigger EDMA hang recovery
echo 1 > /proc/sys/net/edma/edma_hang_recover

# Ensure EDMA hang recovery completes
while [ $(cat /proc/sys/net/edma/edma_hang_recover) == "1" ]; do
	if [[ $timeout_count -ge max_recovery_time ]]; then
		echo "EDMA attempted recovery but failed" >> /var/log/edma_recovery.log
		exit 1
	fi

	sleep 1
	timeout_count=$((timeout_count + 1))
done

/etc/init.d/network start

sleep 2

insmod_if_present ath12k probe_order=0x213
insmod_if_present ath12k_wifi7
insmod_if_present ath12k_wifi8
insmod_if_present qca-wifi-nss-plugins

exit 0

