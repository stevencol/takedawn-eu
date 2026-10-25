#!/system/bin/sh
# android_sample.sh <seconds> <package>: runs ON the device (adb shell sh),
# pushed there by android_race_power.sh. Once a second it prints what an
# unrooted shell may read: every core's /proc/stat line, each cpufreq
# policy's time_in_state, the thermal zones of the CPU, GPU, skin and
# battery, the game process's CPU ticks and, where the kernel lets the
# shell read them (not on a Xiaomi), the battery's current and voltage.
# At the start and the end, every thread of the game with its ticks.
# android_power.py turns the lines into a summary.
#
#   t <ms since boot>
#   c cpuN user nice system idle iowait irq softirq
#   f policyN <cpus> <freq>:<time> ...
#   z <zone type> <millidegrees>
#   p <utime+stime of the process>
#   b <current_now> <voltage_now>
#   th0|th1 <thread name> <utime+stime>
SECS=${1:-60}
PKG=${2:-com.stevencol.takedawn}
pid=$(pidof "$PKG")
[ -n "$pid" ] || { echo "no process $PKG" >&2; exit 1; }
echo "hz $(getconf CLK_TCK 2>/dev/null || echo 100)"
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    echo "policy ${p##*/} $(cat $p/related_cpus)"
done
zones=""
for z in /sys/class/thermal/thermal_zone*; do
    ty=$(cat $z/type 2>/dev/null)
    case "$ty" in
        *cpu*|*CPU*|*gpu*|*GPU*|*skin*|*SKIN*|*batt*|*BAT*|*quiet*|*soc*|*SOC*|AP|ap*) zones="$zones $z" ;;
    esac
done
zones_ok=""
for z in $zones; do cat $z/temp > /dev/null 2>&1 && { zones_ok=1; break; }; done
# utime + stime: fields 14 and 15, counted after the ")" that ends the name
# (a name may hold spaces).
ticks() { awk '{ sub(/.*\) /, ""); print $12 + $13 }' "$1" 2>/dev/null; }
threads() {
    for t in /proc/$pid/task/*; do
        echo "$1 $(tr ' ' _ < $t/comm 2>/dev/null) $(ticks $t/stat)"
    done
}
threads th0
i=0
while [ $i -le "$SECS" ]; do
    echo "t $(cut -d' ' -f1 /proc/uptime | tr -d .)0"
    grep '^cpu[0-9]' /proc/stat | sed 's/^/c /'
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        echo "f ${p##*/} $(tr ' ' ':' < $p/stats/time_in_state | tr '\n' ' ')"
    done
    for z in $zones; do echo "z $(cat $z/type) $(cat $z/temp)"; done 2>/dev/null
    # No zone the shell may read (a Samsung): the thermal HAL's own figures
    # (AP, BAT, SKIN, ...), every fifth second, as millidegrees.
    if [ -z "$zones_ok" ] && [ $((i % 5)) = 0 ]; then
        dumpsys thermalservice 2>/dev/null | sed -n '/Current temperatures from HAL/,/Current cooling/p' \
            | sed -n 's/.*mValue=\([0-9.]*\),.*mName=\([^,]*\),.*/\2 \1/p' \
            | awk '$2 > 0 { printf "z %s %d\n", $1, $2 * 1000 }'
    fi
    echo "p $(ticks /proc/$pid/stat)"
    cur=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
    [ -n "$cur" ] && echo "b $cur $(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)"
    i=$((i + 1))
    sleep 1
done
threads th1
