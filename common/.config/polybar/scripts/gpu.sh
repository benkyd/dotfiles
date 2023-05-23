nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | awk '{printf "%02d\n", $1}'
