FROM ubuntu:22.04

RUN apt update && \
    apt install -y --no-install-recommends \
        curl \
        gosu \
        network-manager \
        python3 \
        python3-pip \
        python-is-python3 \
        sudo \
        systemd \
        ssh \
        wireless-tools \
        cifs-utils \
        smbclient \
        rsync \
    && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir "boxsdk<4"
RUN pip3 install --no-cache-dir python-dotenv

ARG USERNAME=developer
ARG UID=1000
RUN useradd -m $USERNAME && \
		echo "$USERNAME:$USERNAME" | chpasswd && \
		usermod --shell /bin/bash $USERNAME && \
		usermod -aG sudo $USERNAME && \
		mkdir -p /etc/sudoers.d/ && \
		echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME && \
		chmod 0440 /etc/sudoers.d/$USERNAME && \
		usermod  --uid $UID $USERNAME && \
		groupmod --gid $UID $USERNAME

ENV HOME /home/$USERNAME
WORKDIR $HOME
RUN mkdir -p $HOME/.ssh && chown $USERNAME:$USERNAME $HOME/.ssh

COPY entrypoint.sh /entrypoint.sh
COPY ./ $HOME/
RUN touch $HOME/.env

ENTRYPOINT [ "/entrypoint.sh" ]
