# Настройка связки DataDog + RabbitMQ

[DataDog](https://www.datadoghq.com/) - система мониторинга состояния сервера, обладающая широким спектром возможностей.
Данная система является клиент-серверной, т.е. на контролируемом сервере устанавливается ТОЛЬКО агент, который отсылает метрики на сервера DataDog.

---

## Подготовка

1. [Регистрация](https://app.datadoghq.com/signup) (создание личного кабинета на стороне DataDog, откуда и осуществляется мониторинг)
2. [Получение API-ключа](https://app.datadoghq.eu/account/settings#api)

---

## 1. Подключение Docker-интеграции

Данная интеграция позволяет мониторить состояние запущенных на сервере контейнеров (на достаточно высоком уровне абстракции: CPU, RAM, I/O и т.д.), не анализируя специфичные для запущенных в контейнерах приложений метрики.

***./docker-compose.yml:***

```yaml
version: '3.3'
services:
    ...other services...

    datadog-agent:
        image: datadog/agent:7.26.0-jmx
        env_file:
            - ./datadog/.env
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro  # с помощью вольюмов осуществляется
            - /proc/:/host/proc/:ro                         # сбор метрик с контейнеров/сервера
            - /sys/fs/cgroup/:/host/sys/fs/cgroup:ro

    ...more other services...
```

***./datadog.env:***

```yaml
DD_API_KEY=<YOUR_DATADOG_API_KEY>
DD_SITE=<YOUR_DATADOG_DOMAIN>

DD_PROCESS_AGENT_ENABLED=true   # позволяет просматривать процессы сервера/контейнеров в DataDog
```

Результаты настроек доступны по [ссылке](https://app.datadoghq.eu/containers):

*Ссылки*:

1. [Документация](https://docs.datadoghq.com/integrations/faq/compose-and-the-datadog-agent/) по базовой настройке связки DataDog/Docker/Docker Compose;
2. Базовая [документация](https://docs.datadoghq.com/agent/docker/?tab=standard) по Datadog Agent.

<br>

## 2. Подключение RabbitMQ-интеграции

Данная интеграция позволяет отслеживать специфичные для RabbitMQ метрики и его логи.

***./docker-compose.yml:***

```yaml
version: '3.3'
services:
    ...other services...

    rabbitmq:
        build:                          # кастомный образ необходим для задания
            context: ./rabbitmq         # RabbitMQ кастомного файла настроек
            dockerfile: ./Dockerfile
        ports:
            - 5672:5672
        volumes:
            - ./rabbitmq_logs:/rabbitmq_logs  # вольюм для хранения папки (файла) с логами
        labels:
            com.datadoghq.ad.check_names: '["rabbitmq"]'    # на основе этого лейбла DataDog определяет, какое приложение работает в контейнере (не менять!)
            com.datadoghq.ad.init_configs: '[{}]'   # инициализирующие настройки для взаимодействия DataDog и RabbitMQ (не менять!)
            com.datadoghq.ad.instances: >-  # основной блок настройки соединения DataDog и RabbitMQ
                [{
                    "rabbitmq_api_url": "http://%%host%%:15672/api/", # URL-адрес API RabbitMQ с шаблонной переменной имени хоста
                    "username": "<DATADOG_USER>",      # имя пользователя и его пароль
                    "password": "DATADOG_PASSWORD"      № в RabbitMQ для мониторинга
                }]
            com.datadoghq.ad.logs: >-
                [{
                    "type": "file", # тип источника логов
                    "source": "rabbitmq", # название интеграции (не менять!)
                    "service": "rabbitmq",  # имя сервиса для отображение в UI DataDog
                    "path": "/rabbitmq_logs/rabbitmq.logs",  # путь до файла с логами (внутри контейнера DataDog-агента!)
                    "log_processing_rules": [{  # блок правил обработки логов
                        "type": "multi_line",   # сообщение DataDog`у о том, что логи могут быть многострочными
                        "name": "logs",
                        "pattern": "\\d{4}-\\d{2}-\\d{2}" # паттерн начала унарного лог-сообщения
                    }]
                }]

    datadog-agent:
        image: datadog/agent:7.26.0-jmx
        env_file:
            - ./datadog.env
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock:ro
            - /proc/:/host/proc/:ro
            - /sys/fs/cgroup/:/host/sys/fs/cgroup:ro
            - /opt/datadog-agent/run:/opt/datadog-agent/run:rw  # вольюм позволяет сохранять логи локально на случай непредвиденных ситуаций
            - ./rabbitmq_logs:/rabbitmq_logs    # вольюм прокидывает логи RabbitMQ-контейнера в DataDog-контейнер

    ...more other services...
```

***./rabbitmq/.env:***

```yaml
RABBITMQ_CONFIG_FILE=/rabbitmq.conf
RABBITMQ_LOGS=/rabbitmq_logs/rabbitmq.logs
RABBITMQ_PID_FILE=/rabbitmq.pid

DATADOG_USER=<DATADOG_USER>        # пользователь DataDog для мониторинга RabbitMQ
DATADOG_PASSWORD=<DATADOG_PASSWORD>   # и его пароль

```

***./rabbitmq/Dockerfile:***

```Dockerfile
FROM rabbitmq:3.8.14-management

RUN mkdir /rabbitmq_logs            # создание директории
RUN chmod -R 777 /rabbitmq_logs     # для лог-файла с необходимыми правами

COPY ./rabbitmq.conf /rabbitmq.conf     # копирование кастомного конфиг-файла для RabbitMQ

COPY ./init.sh /init.sh     # копирование кастомной точки старта RabbitMQ,
RUN chmod +x /init.sh       # в которой создается пользователь для мониторинга

CMD ["/init.sh"]
```

***./rabbitmq/init.sh***

```bash
#!/bin/sh

( rabbitmqctl wait --timeout 60 $RABBITMQ_PID_FILE ; \      # ожидание запуска RabbitMQ
rabbitmqctl add_user $DATADOG_USER $DATADOG_PASSWORD 2>/dev/null ; \    # создание пользователя с паролем для мониторинга RabbitMQ
rabbitmqctl set_user_tags $DATADOG_USER monitoring ; \      # добавление пользователю тега
rabbitmqctl set_permissions -p / $DATADOG_USER  "^aliveness-test$" "^amq\.default$" ".*") &     # выдача пользователю прав на мониторинг

rabbitmq-server
```

***./rabbitmq/rabbitmq.conf:***

```configuration
...other configs...

loopback_users.guest = false    # запрет на локальное подключение к RabbitMQ гостевому пользователю 
listeners.tcp.default = 5672    # порт подключения к RabbitMQ
management.tcp.port = 15672     # порт UI RabbitMQ для мониторинга
log.dir = /rabbitmq_logs        # путь до папки с логами
log.file = rabbitmq.logs        # название файла с логами
log.file.level = debug          # уровень логирования

...more other configs...
```

***./datadog.env:***

```yaml
DD_API_KEY=<DATADOG_API_KEY>
DD_SITE=<DATADOG_DOMAIN>

DD_PROCESS_AGENT_ENABLED=true   # позволяет DataDog-агенту просматривать процессы сервера/контейнеров в DataDog
DD_LOGS_ENABLED=true    # позволяет DataDog-агенту собирать логи с сервера/контейнеров
DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true   # включает у DataDog-агента сбор логов со всех контейнеров
```

Ссылки:

1. Базовая [документация](https://docs.datadoghq.com/integrations/rabbitmq/?tab=containerized) по настройке RabbitMQ-интеграции в Docker;
2. Описание [rabbitmq.conf](https://www.rabbitmq.com/configure.html) с подробным разъяснением настроек;
3. [Статья](https://docs.datadoghq.com/agent/docker/log/?tab=dockercompose) по настройке логирования DataDog-агентом;
4. [Статья](https://docs.datadoghq.com/agent/docker/integrations/?tab=docker) по настройке автообнаружения интеграций DataDog-агентом;
5. [Параметры](https://github.com/DataDog/integrations-core/blob/master/rabbitmq/datadog_checks/rabbitmq/data/conf.yaml.example) настройки RabbitMQ в DataDog;
6. [Документация](https://docs.datadoghq.com/agent/faq/template_variables/) по шаблонным переменным.
