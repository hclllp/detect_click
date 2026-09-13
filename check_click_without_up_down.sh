timeout {lv=toutime} sh -c '

SCREEN_X=1200
SCREEN_Y=2670

RAW_X_MAX=119999
RAW_Y_MAX=266999


# MacroDroid输入：像素坐标

PX1={lv=x1}
PY1={lv=y1}

PX2={lv=x2}
PY2={lv=y2}



# 像素 -> raw

RX1=$((PX1 * RAW_X_MAX / (SCREEN_X-1)))
RY1=$((PY1 * RAW_Y_MAX / (SCREEN_Y-1)))

RX2=$((PX2 * RAW_X_MAX / (SCREEN_X-1)))
RY2=$((PY2 * RAW_Y_MAX / (SCREEN_Y-1)))



x=0
y=0

touch_down=0



getevent -lt /dev/input/event7 |

while IFS= read -r line
do

    case "$line" in


    *"ABS_MT_TRACKING_ID"*)

        raw=$(echo "$line" | awk "{print \$NF}")


        if [ "$raw" = "ffffffff" ]
        then
            touch_down=0
        else
            touch_down=1
        fi

        ;;



    *"ABS_MT_POSITION_X"*)

        raw=$(echo "$line" | awk "{print \$NF}")

        x=$((16#$raw))

        ;;



    *"ABS_MT_POSITION_Y"*)

        raw=$(echo "$line" | awk "{print \$NF}")

        y=$((16#$raw))

        ;;



    *"EV_SYN"*"SYN_REPORT"*)

        if [ "$touch_down" -eq 1 ]
        then

            if [ "$x" -ge "$RX1" ] &&
               [ "$x" -le "$RX2" ] &&
               [ "$y" -ge "$RY1" ] &&
               [ "$y" -le "$RY2" ]
            then

                echo 1
                exit 0

            fi

        fi

        ;;

    esac

done

'

ret=$?

if [ "$ret" -eq 124 ]
then
    echo 0
fi