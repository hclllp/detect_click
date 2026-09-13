#!/system/bin/sh

# ============================================================
# 基本参数
# ============================================================

SCREEN_X=1200
SCREEN_Y=2670

RAW_X_MAX=119999
RAW_Y_MAX=266999

# # 检测区域，单位：屏幕像素
# PX1=10
# PX2=1100
# PY1=10
# PY2=1300

# # 检测模式
# CHECK_DOWN=True
# CHECK_UP=True


# ============================================================
# 参数处理
# ============================================================

# 防止区域坐标反向
if [ "$PX1" -gt "$PX2" ]; then
    tmp=$PX1
    PX1=$PX2
    PX2=$tmp
fi

if [ "$PY1" -gt "$PY2" ]; then
    tmp=$PY1
    PY1=$PY2
    PY2=$tmp
fi


# ============================================================
# 屏幕坐标 → 原始触摸坐标
# ============================================================

RX1=$((PX1 * RAW_X_MAX / (SCREEN_X - 1)))
RX2=$((PX2 * RAW_X_MAX / (SCREEN_X - 1)))

RY1=$((PY1 * RAW_Y_MAX / (SCREEN_Y - 1)))
RY2=$((PY2 * RAW_Y_MAX / (SCREEN_Y - 1)))


# ============================================================
# 全局状态
# ============================================================

x=0
y=0

has_x=0
has_y=0


# ============================================================
# 判断当前坐标是否在区域内
# ============================================================

in_area()
{
    [ "$x" -ge "$RX1" ] &&
    [ "$x" -le "$RX2" ] &&
    [ "$y" -ge "$RY1" ] &&
    [ "$y" -le "$RY2" ]
}


# ============================================================
# 读取一行 getevent
#
# 所有三个检测函数都从 stdin 读取。
# 主流程只启动一个 getevent。
# ============================================================

read_event()
{
    IFS= read -r line
}


# ============================================================
# 1. check_area
#
# 普通区域检测：
#
# 持续检测 X/Y。
#
# X 和 Y 不要求出现在同一个 SYN_REPORT 中。
# 只要曾经获得过有效 X/Y，就一直缓存。
#
# 每次 SYN_REPORT 时检查当前缓存坐标。
#
# 检测成功：
#     return 0
#
# 检测失败：
#     return 1
# ============================================================

check_area()
{
    while read_event
    do
        case "$line" in

            *"ABS_MT_POSITION_X"*)
                raw=$(echo "$line" | awk '{print $NF}')
                x=$((16#$raw))
                has_x=1
                ;;

            *"ABS_MT_POSITION_Y"*)
                raw=$(echo "$line" | awk '{print $NF}')
                y=$((16#$raw))
                has_y=1
                ;;

            *"EV_SYN"*"SYN_REPORT"*)

                if [ "$has_x" -eq 1 ] &&
                   [ "$has_y" -eq 1 ]
                then
                    if in_area
                    then
                        return 0
                    fi
                fi
                ;;

        esac
    done

    return 1
}


# ============================================================
# 2. check_DOWN_area
#
# 等待一次完整的 DOWN。
#
# 逻辑上匹配：
#
#   BTN_TOUCH       DOWN
#   BTN_TOOL_FINGER DOWN
#   TRACKING_ID     xxxx
#   POSITION_X      xxxx
#   POSITION_Y      xxxx
#
# 这些事件不要求连续。
# 只要出现在同一个 SYN_REPORT 前的事件帧中即可。
#
# 检测到 DOWN 且坐标在区域：
#     return 0
#
# 检测到 DOWN 但不在区域：
#     return 1
#
# 注意：
# x/y 会同时更新到全局缓存。
# ============================================================

check_DOWN_area()
{
    got_touch=0
    got_finger=0
    got_tracking=0
    got_x=0
    got_y=0

    while read_event
    do
        case "$line" in

            *"EV_KEY"*"BTN_TOUCH"*"DOWN"*)
                got_touch=1
                ;;

            *"EV_KEY"*"BTN_TOOL_FINGER"*"DOWN"*)
                got_finger=1
                ;;

            *"ABS_MT_TRACKING_ID"*)
                raw=$(echo "$line" | awk '{print $NF}')

                if [ "$raw" != "ffffffff" ]
                then
                    got_tracking=1
                fi
                ;;

            *"ABS_MT_POSITION_X"*)
                raw=$(echo "$line" | awk '{print $NF}')
                x=$((16#$raw))
                has_x=1
                got_x=1
                ;;

            *"ABS_MT_POSITION_Y"*)
                raw=$(echo "$line" | awk '{print $NF}')
                y=$((16#$raw))
                has_y=1
                got_y=1
                ;;

            *"EV_SYN"*"SYN_REPORT"*)

                if [ "$got_touch" -eq 1 ] &&
                   [ "$got_finger" -eq 1 ] &&
                   [ "$got_tracking" -eq 1 ] &&
                   [ "$got_x" -eq 1 ] &&
                   [ "$got_y" -eq 1 ]
                then

                    if in_area
                    then
                        return 0
                    else
                        return 1
                    fi
                fi

                # 当前 frame 结束
                got_touch=0
                got_finger=0
                got_tracking=0
                got_x=0
                got_y=0
                ;;

        esac
    done

    return 1
}


# ============================================================
# 3. check_UP_area
#
# 从当前事件流开始持续追踪 X/Y。
#
# 每出现：
#
#   ABS_MT_POSITION_X
#   ABS_MT_POSITION_Y
#
# 就更新全局 x/y。
#
# 然后等待：
#
#   BTN_TOUCH       UP
#   BTN_TOOL_FINGER UP
#
# 两个都出现后，认为触摸结束。
#
# 此时使用最后一次缓存的 x/y 判断区域。
#
# 特别重要：
#
# UP 所在的 frame 可能没有 X/Y。
#
# 所以这里绝对不能要求：
#
#   UP frame 必须同时包含 X/Y
#
# 而是使用此前缓存的最后坐标。
#
# 检测到 UP 且最终坐标在区域：
#     return 0
#
# 检测到 UP 但不在区域：
#     return 1
# ============================================================

check_UP_area()
{
    got_touch_up=0
    got_finger_up=0

    while read_event
    do
        case "$line" in

            *"ABS_MT_POSITION_X"*)
                raw=$(echo "$line" | awk '{print $NF}')
                x=$((16#$raw))
                has_x=1
                ;;

            *"ABS_MT_POSITION_Y"*)
                raw=$(echo "$line" | awk '{print $NF}')
                y=$((16#$raw))
                has_y=1
                ;;

            *"EV_KEY"*"BTN_TOUCH"*"UP"*)
                got_touch_up=1
                ;;

            *"EV_KEY"*"BTN_TOOL_FINGER"*"UP"*)
                got_finger_up=1
                ;;

            *"EV_SYN"*"SYN_REPORT"*)

                if [ "$got_touch_up" -eq 1 ] &&
                   [ "$got_finger_up" -eq 1 ]
                then

                    if [ "$has_x" -eq 1 ] &&
                       [ "$has_y" -eq 1 ] &&
                       in_area
                    then
                        return 0
                    else
                        return 1
                    fi
                fi

                got_touch_up=0
                got_finger_up=0
                ;;

        esac
    done

    return 1
}


# ============================================================
# 主流程
# ============================================================

if [ "$CHECK_DOWN" = "False" ] &&
   [ "$CHECK_UP" = "False" ]
then

    # --------------------------------------------------------
    # 模式 1：
    #
    # 只检测手指是否进入区域
    # --------------------------------------------------------

    if check_area
    then
        echo 1
        exit 0
    else
        echo 0
        exit 0
    fi


elif [ "$CHECK_DOWN" = "True" ]
then

    # --------------------------------------------------------
    # 模式 2：
    #
    # 检测 DOWN
    #
    # 如果 CHECK_UP=False：
    #     DOWN 在区域 → 1
    #
    # 如果 CHECK_UP=True：
    #     DOWN 在区域
    #          ↓
    #     持续检测 UP
    #          ↓
    #     UP 最终位置在区域 → 1
    #          ↓
    #     否则重新等待下一次 DOWN
    # --------------------------------------------------------

    while true
    do

        if check_DOWN_area
        then

            # DOWN 在区域

            if [ "$CHECK_UP" = "False" ]
            then
                echo 1
                exit 0
            fi


            # DOWN + UP 模式
            if check_UP_area
            then
                echo 1
                exit 0
            fi

            # UP 不在区域
            # 回到这里继续等待下一次 DOWN

        fi

    done


elif [ "$CHECK_DOWN" = "False" ] &&
     [ "$CHECK_UP" = "True" ]
then

    # --------------------------------------------------------
    # 模式 3：
    #
    # 只检测 UP
    #
    # 每次 UP：
    #     最终位置在区域 → 1
    #     不在区域 → 继续等待下一次 UP
    # --------------------------------------------------------

    while true
    do

        if check_UP_area
        then
            echo 1
            exit 0
        fi
    done

fi


exit 0