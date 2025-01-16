FROM ubuntu:22.04

RUN apt update && \
	apt install -y --no-install-recommends \
	locales \
	&& \
	apt clean && \
	rm -rf /var/lib/apt/lists/*

RUN apt update && apt install -y --no-install-recommends \
autoconf automake libtool tar wget make gcc libpcap-dev \
&& apt clean && rm -rf /var/lib/apt/lists/*

RUN apt update && \
	apt install -y --no-install-recommends \
    curl \
	network-manager \
	bluetooth \
	bluez \
	bluez-tools \
	python3 \
    python3-dbus \
	python3-pip \
	python-is-python3 \
	sudo \
	systemd \
    wireless-tools \
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

COPY create_list.sh $HOME/create_list.sh
COPY can_upload_report.sh $HOME/can_upload_report.sh
COPY get_duration.sh $HOME/get_duration.sh
COPY get_folder_url.py $HOME/get_folder_url.py
COPY get_log_list.sh $HOME/get_log_list.sh
COPY get_report.sh $HOME/get_report.sh
COPY make_issue.py $HOME/make_issue.py
COPY notice_error.py $HOME/notice_error.py
COPY notification.sh $HOME/notification.sh
COPY submit_report.sh $HOME/submit_report.sh
COPY upload.py $HOME/upload.py
COPY entrypoint.sh /entrypoint.sh
COPY .env/ $HOME/.env

ENTRYPOINT [ "/entrypoint.sh" ]