FROM ubuntu:22.04

RUN apt update && \
	apt install -y --no-install-recommends \
    curl \
	network-manager \
	python3 \
	python3-pip \
	python-is-python3 \
	sudo \
	systemd \
    wireless-tools \
	cifs-utils \
	smbclient \
	rsync \
	&& \
	apt clean && \
	rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir boxsdk
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

USER $USERNAME
ENV HOME /home/$USERNAME
WORKDIR $HOME

COPY entrypoint.sh /entrypoint.sh
COPY ./ $HOME/
RUN touch $HOME/.env

ENTRYPOINT [ "/entrypoint.sh" ]