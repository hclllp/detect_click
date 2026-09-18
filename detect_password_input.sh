#!/system/bin/sh

# Record one Android pattern-lock gesture and print the grid points it crosses.
# Coordinates and R are screen-pixel values; getevent reports raw coordinates.

EVENT_DEVICE=${EVENT_DEVICE:-/dev/input/event7}
SCREEN_X=${SCREEN_X:-1200}
SCREEN_Y=${SCREEN_Y:-2670}
RAW_X_MAX=${RAW_X_MAX:-119999}
RAW_Y_MAX=${RAW_Y_MAX:-266999}

: "${Z_X1:=0}"; : "${Z_Y1:=700}"
: "${Z_X2:=1200}"; : "${Z_Y2:=2200}"
: "${P1_X:=300}"; : "${P1_Y:=1250}"
: "${P2_X:=600}"; : "${P2_Y:=1250}"
: "${P3_X:=900}"; : "${P3_Y:=1250}"
: "${P4_X:=300}"; : "${P4_Y:=1550}"
: "${P5_X:=600}"; : "${P5_Y:=1550}"
: "${P6_X:=900}"; : "${P6_Y:=1550}"
: "${P7_X:=300}"; : "${P7_Y:=1850}"
: "${P8_X:=600}"; : "${P8_Y:=1850}"
: "${P9_X:=900}"; : "${P9_Y:=1850}"
: "${R:=100}"

usage() {
    echo "Usage: $0 [--z X1 Y1 X2 Y2] [--p1 X Y] ... [--p9 X Y] [--radius R]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --z) [ "$#" -ge 5 ] || { usage; exit 2; }; Z_X1=$2; Z_Y1=$3; Z_X2=$4; Z_Y2=$5; shift 5 ;;
        --radius) [ "$#" -ge 2 ] || { usage; exit 2; }; R=$2; shift 2 ;;
        --p1|--p2|--p3|--p4|--p5|--p6|--p7|--p8|--p9)
            [ "$#" -ge 3 ] || { usage; exit 2; }
            case "$1" in
                --p1) P1_X=$2; P1_Y=$3 ;; --p2) P2_X=$2; P2_Y=$3 ;;
                --p3) P3_X=$2; P3_Y=$3 ;; --p4) P4_X=$2; P4_Y=$3 ;;
                --p5) P5_X=$2; P5_Y=$3 ;; --p6) P6_X=$2; P6_Y=$3 ;;
                --p7) P7_X=$2; P7_Y=$3 ;; --p8) P8_X=$2; P8_Y=$3 ;;
                --p9) P9_X=$2; P9_Y=$3 ;;
            esac
            shift 3
            ;;
        --help|-h) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

is_integer() { case "$1" in ''|*[!0-9-]*|-) return 1 ;; *) return 0 ;; esac; }
for value in "$Z_X1" "$Z_Y1" "$Z_X2" "$Z_Y2" "$R" \
    "$P1_X" "$P1_Y" "$P2_X" "$P2_Y" "$P3_X" "$P3_Y" \
    "$P4_X" "$P4_Y" "$P5_X" "$P5_Y" "$P6_X" "$P6_Y" \
    "$P7_X" "$P7_Y" "$P8_X" "$P8_Y" "$P9_X" "$P9_Y"; do
    is_integer "$value" || { echo 0; exit 0; }
done
[ "$R" -ge 0 ] || { echo 0; exit 0; }

if [ "$Z_X1" -gt "$Z_X2" ]; then temp=$Z_X1; Z_X1=$Z_X2; Z_X2=$temp; fi
if [ "$Z_Y1" -gt "$Z_Y2" ]; then temp=$Z_Y1; Z_Y1=$Z_Y2; Z_Y2=$temp; fi

# Keep the temporary path file beside the script's invocation directory.  This
# avoids relying on Android directories that rish/Termux may not be allowed to
# write.  Set PATH_FILE explicitly only when another writable location is known.
PATH_FILE=${PATH_FILE:-./detect_password_input_$$.path}
: > "$PATH_FILE" 2>/dev/null || { echo 0; exit 0; }
cleanup() {
    rm -f "$PATH_FILE"
}
trap cleanup EXIT HUP INT TERM

command -v getevent >/dev/null 2>&1 || { echo 0; exit 0; }

in_zone() {
    [ "$screen_x" -ge "$Z_X1" ] && [ "$screen_x" -le "$Z_X2" ] &&
    [ "$screen_y" -ge "$Z_Y1" ] && [ "$screen_y" -le "$Z_Y2" ]
}

# Produce the point IDs ordered by the first sampled path coordinate that is
# within R of each point.  Squared distances avoid a floating-point dependency.
password_from_path() {
    awk -F, -v r="$R" \
        -v p1="$P1_X,$P1_Y" -v p2="$P2_X,$P2_Y" -v p3="$P3_X,$P3_Y" \
        -v p4="$P4_X,$P4_Y" -v p5="$P5_X,$P5_Y" -v p6="$P6_X,$P6_Y" \
        -v p7="$P7_X,$P7_Y" -v p8="$P8_X,$P8_Y" -v p9="$P9_X,$P9_Y" '
            BEGIN {
                split(p1, point1, ","); split(p2, point2, ","); split(p3, point3, ",")
                split(p4, point4, ","); split(p5, point5, ","); split(p6, point6, ",")
                split(p7, point7, ","); split(p8, point8, ","); split(p9, point9, ",")
                px[1]=point1[1]; py[1]=point1[2]; px[2]=point2[1]; py[2]=point2[2]
                px[3]=point3[1]; py[3]=point3[2]; px[4]=point4[1]; py[4]=point4[2]
                px[5]=point5[1]; py[5]=point5[2]; px[6]=point6[1]; py[6]=point6[2]
                px[7]=point7[1]; py[7]=point7[2]; px[8]=point8[1]; py[8]=point8[2]
                px[9]=point9[1]; py[9]=point9[2]
                radius2 = r * r
            }
            {
                for (i = 1; i <= 9; i++) {
                    if (!(i in order)) {
                        dx = $1 - px[i]; dy = $2 - py[i]
                        if (dx * dx + dy * dy <= radius2) order[i] = NR
                    }
                }
            }
            END {
                result = ""
                for (position = 1; position <= 9; position++) {
                    selected = 0
                    for (i = 1; i <= 9; i++)
                        if ((i in order) && !used[i] && (!selected || order[i] < order[selected])) selected = i
                    if (selected) { result = result selected; used[selected] = 1 }
                }
                if (result != "") print result
            }
        ' "$PATH_FILE"
}

raw_x=0; raw_y=0; have_x=0; have_y=0
frame_x=0; frame_y=0; frame_tracking_down=0
frame_touch_down=0; frame_finger_down=0
frame_touch_up=0; frame_finger_up=0
path_active=0

# Keep the event loop in the pipeline's right-hand process.  It can exit as
# soon as a completed gesture is found, which closes the pipe to getevent.
getevent -lt "$EVENT_DEVICE" 2>/dev/null | {
while IFS= read -r line; do
    case "$line" in
        *"ABS_MT_POSITION_X"*)
            raw=${line##* }
            raw_x=$((0x$raw)); have_x=1; frame_x=1
            ;;
        *"ABS_MT_POSITION_Y"*)
            raw=${line##* }
            raw_y=$((0x$raw)); have_y=1; frame_y=1
            ;;
        *"ABS_MT_TRACKING_ID"*)
            raw=${line##* }
            [ "$raw" = "ffffffff" ] || frame_tracking_down=1
            ;;
        *"EV_KEY"*"BTN_TOUCH"*"DOWN"*)
            frame_touch_down=1
            ;;
        *"EV_KEY"*"BTN_TOOL_FINGER"*"DOWN"*)
            frame_finger_down=1
            ;;
        *"EV_KEY"*"BTN_TOUCH"*"UP"*)
            frame_touch_up=1
            ;;
        *"EV_KEY"*"BTN_TOOL_FINGER"*"UP"*)
            frame_finger_up=1
            ;;
        *"EV_SYN"*"SYN_REPORT"*)
            if [ "$have_x" -eq 1 ] && [ "$have_y" -eq 1 ]; then
                screen_x=$((raw_x * (SCREEN_X - 1) / RAW_X_MAX))
                screen_y=$((raw_y * (SCREEN_Y - 1) / RAW_Y_MAX))
            fi

            # A DOWN must be a complete touch frame: both key notifications,
            # a non-terminal tracking ID, and a paired X/Y coordinate.
            if [ "$path_active" -eq 0 ] && [ "$frame_tracking_down" -eq 1 ] &&
               [ "$frame_touch_down" -eq 1 ] && [ "$frame_finger_down" -eq 1 ] &&
               [ "$frame_x" -eq 1 ] && [ "$frame_y" -eq 1 ] && in_zone; then
                path_active=1
                printf '%s,%s\n' "$screen_x" "$screen_y" >> "$PATH_FILE"
            elif [ "$path_active" -eq 1 ] && [ "$have_x" -eq 1 ] &&
                 [ "$have_y" -eq 1 ]; then
                printf '%s,%s\n' "$screen_x" "$screen_y" >> "$PATH_FILE"
            fi

            # The final coordinates can be in an earlier frame, so evaluate
            # the cached coordinate when both key-up notifications arrive.
            if [ "$path_active" -eq 1 ] && [ "$frame_touch_up" -eq 1 ] &&
               [ "$frame_finger_up" -eq 1 ]; then
                if in_zone; then
                    password=$(password_from_path)
                    [ -n "$password" ] && echo "$password" || echo 0
                    exit 0
                fi
                : > "$PATH_FILE"
                path_active=0
            fi
            frame_x=0; frame_y=0; frame_tracking_down=0
            frame_touch_down=0; frame_finger_down=0
            frame_touch_up=0; frame_finger_up=0
            ;;
    esac
done

echo 0
}
exit 0
