FROM centos

ENV LANG=en_US.UTF8
RUN yum install -y python3
RUN yum install -y python3-devel
RUN yum install -y gcc
RUN yum install -y make
RUN yum install -y epel-release
RUN yum install -y redis
RUN pip3 install --user sanic multitimer redis validators
RUN mkdir /app

COPY service.py /app
COPY conf /app
COPY docker-run.sh /app
RUN chmod +x /app/docker-run.sh

EXPOSE 8080
ENV MYAPP_SETTINGS=/app/conf
CMD ["/app/docker-run.sh"]
