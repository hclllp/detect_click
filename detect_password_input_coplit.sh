#!/system/bin/sh

# ============================================================
# detect_password_input.sh
#
# 作用：
#   检测当前屏幕锁屏九宫格上的手指轨迹，并输出按顺序经过的点编号字符串。
#
# 例如：
#   只命中 4、5、7、9 四个点，且对应次序为 O_4 < O_9 < O_7 < O_5
#   则输出：4975
#   否则输出：0
#
# 参数说明：
#   Z 区域：矩形区域（x1,y1）到（x2,y2），默认： (0,700) ~ (1200,2200)
#   P_n：9 个点的坐标，默认：
#        (300,1250), (600,1250), (900,1250)
#        (300,1550), (600,1550), (900,1550)
#        (300,1850), (600,1850), (900,1850)
#   R：距离阈值，默认：100
#
# 支持方式：
#   1) 使用环境变量覆盖默认值，如：
#        Z_X1=0 Z_Y1=700 Z_X2=1200 Z_Y2=2200 R=100 ./detect_password_input.sh
#   2) 或者直接传入参数：
#        ./detect_password_input.sh Z_X1 Z_Y1 Z_X2 Z_Y2 R P1_X P1_Y ... P9_X P9_Y
#
# 输出：
#   echo password_input; exit 0
#   echo 0; exit 0
# ============================================================

EVENT_DEVICE=${EVENT_DEVICE:-/dev/input/event7}

# 默认的触摸区域 Z（屏幕像素）
: ${Z_X1:=0}
: ${Z_Y1:=700}
: ${Z_X2:=1200}
: ${Z_Y2:=2200}

# 默认的有效距离 R
: ${R:=100}

# 默认 9 个格点坐标（屏幕像素）
: ${P1_X:=300} ; : ${P1_Y:=1250}
: ${P2_X:=600} ; : ${P2_Y:=1250}
: ${P3_X:=900} ; : ${P3_Y:=1250}
: ${P4_X:=300} ; : ${P4_Y:=1550}
: ${P5_X:=600} ; : ${P5_Y:=1550}
: ${P6_X:=900} ; : ${P6_Y:=1550}
: ${P7_X:=300} ; : ${P7_Y:=1850}
: ${P8_X:=600} ; : ${P8_Y:=1850}
: ${P9_X:=900} ; : ${P9_Y:=1850}

# -------------------------
# 兼容参数传入模式
# -------------------------
if [ "$#" -ge 4 ]; then
    Z_X1=$1
    Z_Y1=$2
    Z_X2=$3
    Z_Y2=$4
    shift 4
fi

if [ "$#" -ge 1 ]; then
    R=$1
    shift
fi

if [ "$#" -ge 18 ]; then
    P1_X=$1; P1_Y=$2; shift 2
    P2_X=$1; P2_Y=$2; shift 2
    P3_X=$1; P3_Y=$2; shift 2
    P4_X=$1; P4_Y=$2; shift 2
    P5_X=$1; P5_Y=$2; shift 2
    P6_X=$1; P6_Y=$2; shift 2
    P7_X=$1; P7_Y=$2; shift 2
    P8_X=$1; P8_Y=$2; shift 2
    P9_X=$1; P9_Y=$2; shift 2
fi

# 防止区域坐标反向
if [ "$Z_X1" -gt "$Z_X2" ]; then
    tmp=$Z_X1
    Z_X1=$Z_X2
    Z_X2=$tmp
fi

if [ "$Z_Y1" -gt "$Z_Y2" ]; then
    tmp=$Z_Y1
    Z_Y1=$Z_Y2
    Z_Y2=$tmp
fi

if ! command -v getevent >/dev/null 2>&1; then
    echo 0
    exit 0
fi

if [ ! -e "$EVENT_DEVICE" ]; then
    echo 0
    exit 0
fi

# 下面通过 python 处理事件流与几何计算，使用 shell 作为包装层。
if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
else
    echo 0
    exit 0
fi

exec "$PYTHON_BIN" - "$EVENT_DEVICE" "$Z_X1" "$Z_Y1" "$Z_X2" "$Z_Y2" "$R" \
    "$P1_X" "$P1_Y" "$P2_X" "$P2_Y" "$P3_X" "$P3_Y" \
    "$P4_X" "$P4_Y" "$P5_X" "$P5_Y" "$P6_X" "$P6_Y" \
    "$P7_X" "$P7_Y" "$P8_X" "$P8_Y" "$P9_X" "$P9_Y" <<'PY'

import math
import os
import re
import subprocess
import sys

EVENT_DEVICE = sys.argv[1]
Z_X1 = int(sys.argv[2])
Z_Y1 = int(sys.argv[3])
Z_X2 = int(sys.argv[4])
Z_Y2 = int(sys.argv[5])
R = float(sys.argv[6])

points = []
values = list(map(int, sys.argv[7:]))
for i in range(0, len(values), 2):
    x = values[i]
    y = values[i + 1]
    points.append((x, y))

SCREEN_X = 1200
SCREEN_Y = 2670
RAW_X_MAX = 119999
RAW_Y_MAX = 266999


def parse_value(raw_value):
    raw_value = raw_value.strip()
    try:
        return int(raw_value, 16)
    except ValueError:
        try:
            return int(raw_value)
        except ValueError:
            return None


def raw_to_screen(raw_x, raw_y):
    sx = int(raw_x * SCREEN_X / (RAW_X_MAX - 1)) if RAW_X_MAX > 1 else 0
    sy = int(raw_y * SCREEN_Y / (RAW_Y_MAX - 1)) if RAW_Y_MAX > 1 else 0
    return sx, sy


def in_zone(x, y):
    return Z_X1 <= x <= Z_X2 and Z_Y1 <= y <= Z_Y2


def read_event_stream(device):
    # 直接以 getevent 流为输入，用于检测 DOWN/UP 和坐标轨迹
    proc = subprocess.Popen(
        ['getevent', '-lt', device],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )
    try:
        for line in proc.stdout:
            yield line.rstrip('\n')
    finally:
        try:
            proc.terminate()
        except Exception:
            pass
        try:
            proc.wait(timeout=1)
        except Exception:
            pass


path = []
started = False
last_x = None
last_y = None
has_x = False
has_y = False
frame_touch_down = False
frame_touch_up = False
frame_finger_down = False
frame_finger_up = False
frame_tracking_valid = False

for line in read_event_stream(EVENT_DEVICE):
    if not line:
        continue

    if 'ABS_MT_POSITION_X' in line:
        raw = line.split()[-1]
        v = parse_value(raw)
        if v is not None:
            last_x = v
            has_x = True

    elif 'ABS_MT_POSITION_Y' in line:
        raw = line.split()[-1]
        v = parse_value(raw)
        if v is not None:
            last_y = v
            has_y = True

    elif 'EV_KEY' in line and 'BTN_TOUCH' in line and 'DOWN' in line:
        frame_touch_down = True
    elif 'EV_KEY' in line and 'BTN_TOOL_FINGER' in line and 'DOWN' in line:
        frame_finger_down = True
    elif 'EV_KEY' in line and 'BTN_TOUCH' in line and 'UP' in line:
        frame_touch_up = True
    elif 'EV_KEY' in line and 'BTN_TOOL_FINGER' in line and 'UP' in line:
        frame_finger_up = True
    elif 'ABS_MT_TRACKING_ID' in line:
        raw = line.split()[-1]
        if raw and raw.lower() != 'ffffffff':
            frame_tracking_valid = True

    elif 'EV_SYN' in line and 'SYN_REPORT' in line:
        if has_x and has_y and last_x is not None and last_y is not None:
            sx, sy = raw_to_screen(last_x, last_y)
            if started:
                path.append((sx, sy))
            elif frame_touch_down and frame_finger_down and frame_tracking_valid and in_zone(sx, sy):
                started = True
                path.append((sx, sy))

        if started and frame_touch_up and frame_finger_up:
            break

        # 当前 frame 结束，重置状态
        last_x = None
        last_y = None
        has_x = False
        has_y = False
        frame_touch_down = False
        frame_touch_up = False
        frame_finger_down = False
        frame_finger_up = False
        frame_tracking_valid = False

# 计算：针对每个格点，找到路径中第一次满足距离 R 的采样点次序
valid_points = []
for point_id, (px, py) in enumerate(points, start=1):
    first_order = None
    for order_idx, (cx, cy) in enumerate(path):
        dist = math.hypot(cx - px, cy - py)
        if dist < R:
            first_order = order_idx
            break
    if first_order is not None:
        valid_points.append((first_order, str(point_id)))

if not valid_points:
    print(0)
    sys.exit(0)

valid_points.sort(key=lambda item: item[0])
password_input = ''.join(pid for _, pid in valid_points)
print(password_input)
sys.exit(0)
PY
