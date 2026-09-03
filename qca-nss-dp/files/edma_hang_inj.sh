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

# Get board name
board=$(cat /tmp/sysinfo/board_name)

# Register offsets from EDMA base (constant across SoCs)
RXFILL_BA_OFF=0x29000
RXFILL_PROD_OFF=0x29004
RXFILL_CONS_OFF=0x29008

# EDMA base address and ring-to-ring offset multiplier vary by SoC
case "$board" in
	*ipq9574*|*ipq5332*)
		edma_base=0x3AB00000
		multiplier=0x1000
		ring_number=4
		RXFILL_SZ_OFF=0x2900C
		;;
	*ipq5424*)
		edma_base=0x3AB00000
		multiplier=0x1000
		ring_number=4
		RXFILL_SZ_OFF=0x29010
		;;
	*ipq9650*)
		edma_base=0x2AD00000
		multiplier=0x100
		ring_number=7
		RXFILL_SZ_OFF=0x29010
		;;
	*ipq5210*)
		edma_base=0x3AD00000
		multiplier=0x100
		ring_number=7
		RXFILL_SZ_OFF=0x29010
		;;
	*)
		echo "Error: Unsupported SoC type $board. Aborting."
		exit 1
		;;
esac

rxfill_corrupt() {
	ring_n=$1
	echo "RXFILL Corrupt: Ring: $ring_n"

	#producer index
	rxfill_prod=$(($edma_base + $RXFILL_PROD_OFF + ($multiplier*$ring_n)))
	echo "rxfill_prod[$ring_n] addr: 0x$(printf "%x" $rxfill_prod) index: " `devmem $rxfill_prod`

	#consumer index
	rxfill_cons=$(($edma_base + $RXFILL_CONS_OFF + ($multiplier*$ring_n)))
	echo "rxfill_cons[$ring_n] addr: 0x$(printf "%x" $rxfill_cons) index: " `devmem $rxfill_cons`

	#base address
	rxfill_ba=$(($edma_base + $RXFILL_BA_OFF + ($multiplier*$ring_n)))
	echo "rxfill_ba[$ring_n] addr: 0x$(printf "%x" $rxfill_ba) index: " `devmem $rxfill_ba`

	#ring size
	rxfill_sz=$(($edma_base + $RXFILL_SZ_OFF + ($multiplier*$ring_n)))
	count=`devmem $rxfill_sz`
	MAX=$(($count - 1))

	cons_index=`devmem $rxfill_cons`

	base_reg=`devmem $rxfill_ba`

	#Inducing corruption at cons_index+32 descriptor
	cons_index_upd=$((cons_index + 32))

	# Ensure +32 doesn't go beyond the MAX value of cons_index
	if [ "$cons_index_upd" -gt "$MAX" ]; then

		# Wrap around if needed
		cons_index_upd=$((cons_index_upd - MAX - 1))
	fi

	reg=$(($base_reg + (16*$cons_index_upd)))

	# Trigger a read to commit the previous write
        devmem $reg 32 0

}

/etc/init.d/network stop

# Check if a ring number is provided
if [ "$#" -eq 0 ]; then
    # If no ring number is provided, use the default value 4
    echo "No ring number provided. Using default value $ring_number."
else
    ring_number="$1"
fi

# Call the function with the selected ring number
rxfill_corrupt "$ring_number"

/etc/init.d/network start

exit 0

