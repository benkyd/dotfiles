#!/bin/sh
GPU_TEMP=$(nvidia-settings -q GPUCoreTemp | grep -m1 GPU | perl -ne 'print $1 if /: (\d+)\./')
GPU_USAGE=$(nvidia-settings -q GPUUtilization -q GPUCoreTemp | grep -oP 'graphics=\K\w+')
echo "$GPU_USAGE $GPU_TEMP.0°C" | awk '{ printf(" GPU:%3s% @ %s \n"), $1, $2 }'
