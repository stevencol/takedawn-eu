# Sourced by the Android test scripts (bash, $ADB set): little_mask prints
# the taskset mask of the device's cores below its top max frequency (a
# Dimensity 1080's six A55, a Snapdragon 8 Elite's six performance cores),
# or ff..ff where every core is of one kind. The scripts' own device-side
# commands (the sampler, the log followers, the liveness poll) run there,
# off the cores the game pins its executor and guest threads to: on an A34
# a sampler's shell pipeline held those for up to 6 ms at a time.
little_mask() {
    $ADB shell 't=0; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq; do
            v=$(cat $f); [ "$v" -gt $t ] && t=$v; done
        m=0; for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq; do
            c=${f#/sys/devices/system/cpu/cpu}; c=${c%%/*}
            [ "$(cat $f)" -lt $t ] && m=$((m | (1 << c))); done
        [ $m = 0 ] && m=-1; printf "%x" $m' 2>/dev/null | tr -d '\r'
}
