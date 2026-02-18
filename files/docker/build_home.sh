# Build dot files in root and construct a default root for the run script.

# Set root
cat << EOF >> /etc/bash.bashrc

# System-wide aliases
alias ls='ls -aFh --color=auto'
alias ll='ls -aFlh --color=auto'
EOF

# Setup default
mkdir -p /home/default -m 777

# Link .cache to /dev/shm/cache
# Use mode 777 to allow non-root users (when running with --user flag) to write to cache
mkdir -p /dev/shm/cache -m 777
mkdir -p /dev/shm/config -m 777
mkdir -p /dev/shm/tmp -m 777

ln -s /dev/shm/cache /home/default/.cache
ln -s /dev/shm/config /home/default/.config
