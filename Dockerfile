FROM ubuntu:24.04@sha256:2198e4c65076e9cb0b3d695219df667c0e3b0072da64ca3c2648aca17dcecaf5

RUN apt-get update && \
    apt-get install -y sudo \
        language-pack-en \
        openssh-server \
        curl \
        vim \
        dnsutils \
        jq \
        rsync \
        git && \
    apt-get clean && \
    mkdir -p /var/run/sshd && \
    mkdir -p /root/.ssh

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

EXPOSE 22

ENV SSH_USER="dev"
ENV SSH_USER_ID="501"
ENV SSH_USER_GID="50"
ENV GITHUB_USER="yuanying"

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D"]
