FROM rabbitmq:3.8.14-management

RUN mkdir /rabbitmq_logs
RUN chmod -R 777 /rabbitmq_logs

COPY ./rabbitmq.conf /rabbitmq.conf

COPY ./init.sh /init.sh
RUN chmod +x /init.sh

CMD ["/init.sh"]
