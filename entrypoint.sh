#!/bin/sh -e

apt-get update
useradd -g ${SSH_USER_GID} -m -s /bin/bash  -u ${SSH_USER_ID} "${SSH_USER}"
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

mkdir -p /home/${SSH_USER}/.ssh
chmod 700 /home/${SSH_USER}/.ssh
curl -L -o /home/${SSH_USER}/.ssh/authorized_keys https://github.com/${GITHUB_USER}.keys
chmod 600 /home/${SSH_USER}/.ssh/*
chown -R ${SSH_USER} /home/${SSH_USER}/.ssh

exec "$@"
