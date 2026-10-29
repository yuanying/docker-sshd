FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

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
