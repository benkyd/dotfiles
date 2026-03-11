if command -v nvidia-smi &> /dev/null
then
    nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | awk '{printf "%02d\n", $1}'
    exit
fi

