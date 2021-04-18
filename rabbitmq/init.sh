#!/bin/sh

( rabbitmqctl wait --timeout 60 $RABBITMQ_PID_FILE ; \
rabbitmqctl add_user $DATADOG_USER $DATADOG_PASSWORD 2>/dev/null ; \
rabbitmqctl set_user_tags $DATADOG_USER monitoring ; \
rabbitmqctl set_permissions -p / $DATADOG_USER  "^aliveness-test$" "^amq\.default$" ".*") &

rabbitmq-server
