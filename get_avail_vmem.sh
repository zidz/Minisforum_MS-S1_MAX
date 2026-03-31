cat /sys/module/ttm/parameters/p* | awk '{print $1 / (1024 * 1024 / 4)}'
sudo dmesg | grep "amdgpu:.*memory"
