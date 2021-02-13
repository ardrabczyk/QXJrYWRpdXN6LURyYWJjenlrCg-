FROM fedora:33

ENV LANG=C.UTF-8
RUN dnf install -y gcc python3-devel redis
# https://src.fedoraproject.org/rpms/python-pip/pull-request/67
RUN pip3 install --root / multitimer redis sanic validators
RUN mkdir /app

COPY service.py /app
COPY conf /app
COPY docker-run.sh /app
RUN chmod +x /app/docker-run.sh

EXPOSE 8080
ENV MYAPP_SETTINGS=/app/conf
CMD ["/app/docker-run.sh"]
