FROM debian:wheezy
MAINTAINER Tomasz Gaweda

ENV http_proxy http://172.17.42.1:8080/
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Install VMD
RUN    apt-get update && apt-get -y install wget                     \
	&& wget -q http://172.17.42.1:9090/vmd-1.9.2beta1.src.tar.gz          \
	&& wget -q http://172.17.42.1:9090/docker-vmd/vmd_install.sh     \
	&& bash vmd_install.sh vmd-*.src.tar.gz

# Create user
RUN 	export uid=1000 gid=1000  \
	&& 	mkdir -p /home/vmd        \
	&&  echo "vmd:x:${uid}:${gid}:vmd,,,:/home/vmd:/bin/bash" >> /etc/passwd \
	&& echo "vmd:x:${uid}:" >> /etc/group                      \
	&& chown ${uid}:${gid} -R /home/vmd

# Prepare container
USER vmd
ENV HOME /home/vmd
CMD vmd
