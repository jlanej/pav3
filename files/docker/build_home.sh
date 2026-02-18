# Build dot files in root and construct a default root for the run script.

# Set root
cat << EOF >> /etc/bash.bashrc

# System-wide aliases
alias ls='ls -aFh --color=auto'
alias ll='ls -aFlh --color=auto'
EOF

# Setup default home directory with cache directories
# Create actual directories instead of symlinks to /dev/shm to ensure
# compatibility when running as non-root user with --user flag.
#
# NOTE: Using mode 777 is intentional for Docker --user compatibility.
# The container is designed to run with arbitrary UIDs (e.g., --user $(id -u):$(id -g)),
# so the cache directories must be world-writable. This is safe in the container context
# where /home/default is a shared scratch space for Snakemake's cache.
mkdir -p /home/default/.cache -m 777
mkdir -p /home/default/.config -m 777

# Make /home/default world-writable so any user can write to it
chmod -R 777 /home/default
