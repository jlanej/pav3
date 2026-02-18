# Build dot files in root and construct a default root for the run script.

# Set root
cat << EOF >> /etc/bash.bashrc

# System-wide aliases
alias ls='ls -aFh --color=auto'
alias ll='ls -aFlh --color=auto'
EOF

# Setup default
mkdir -p /home/default -m 777

# Create .cache and .config as real directories (not symlinks)
# Use mode 777 to allow non-root users (when running with --user flag) to write to cache
# Previously these were symlinks to /dev/shm, but /dev/shm subdirectories don't persist
# across Docker build and runtime, causing FileNotFoundError with --user flag
mkdir -p /home/default/.cache -m 777
mkdir -p /home/default/.config -m 777
