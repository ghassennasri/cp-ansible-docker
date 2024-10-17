# Use an official Ubuntu 20.04 as the base image
FROM ubuntu:20.04

# Set non-interactive mode for apt-get to avoid timezone prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary packages: OpenJDK, SSH, Python3, and other dependencies
RUN apt-get update && \
    apt-get install -y  systemd systemd-sysv openssh-server sudo tzdata openjdk-11-jdk openssh-server python3 && \
    apt-get clean

# Configure timezone to Europe/Paris
RUN ln -fs /usr/share/zoneinfo/Europe/Paris /etc/localtime && dpkg-reconfigure -f noninteractive tzdata
# Setup systemd as the entry point and expose SSH port
STOPSIGNAL SIGRTMIN+3
VOLUME [ "/sys/fs/cgroup" ]
CMD ["/lib/systemd/systemd"]


# Create necessary directories for SSH and set permissions
RUN mkdir -p /run/sshd && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh && \
    echo "export VISIBLE=now" >> /etc/profile

# Copy your public SSH key into the image
COPY id_rsa.pub /root/.ssh/authorized_keys

# Set correct permissions for authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys

# Configure SSH to allow root login with keys
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's@#AuthorizedKeysFile.*@AuthorizedKeysFile %h/.ssh/authorized_keys@' /etc/ssh/sshd_config

# Expose SSH port
EXPOSE 22

# Disable Udev as it is not needed and can cause issues in containers
RUN systemctl mask udev.service systemd-udevd.service
