FROM ubuntu:20.04

RUN apt-get update && \
    apt-get install -y sudo \
        language-pack-en \
        openssh-server \
        curl \
        vim \
        dnsutils \
        jq \
        rsync && \
    apt-get clean && \
    mkdir /var/run/sshd && \
    mkdir /root/.ssh

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
