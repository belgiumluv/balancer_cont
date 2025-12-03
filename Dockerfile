# ===== СЛОЙ 1: сборка Redis из исходников =====
FROM alpine:3.19 AS builder

RUN apk update && apk add --no-cache \
    build-base \
    git \
    linux-headers \
    jemalloc-dev \
    tar \
    bash

WORKDIR /build


ARG LEGO_VERSION=4.23.2
RUN curl -L "https://github.com/go-acme/lego/releases/download/v${LEGO_VERSION}/lego_v${LEGO_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin lego
# Клонируем официальный Redis
RUN git clone https://github.com/redis/redis.git
WORKDIR /build/redis

# При желании можно зафиксировать версию, например:
# RUN git checkout 7.4.0

RUN make -j$(nproc)


# ===== СЛОЙ 2: финальный образ =====
FROM alpine:3.19

# Runtime-зависимости + Python и requests
RUN apk add --no-cache \
    jemalloc \
    bash \
    python3 \
    py3-requests

# Папка Redis
WORKDIR /Redis

# Бинарники Redis
COPY --from=builder /build/redis/src/redis-server /Redis/redis-server
COPY --from=builder /build/redis/src/redis-cli    /Redis/redis-cli

# Конфиг Redis (внешний файл из проекта)
COPY redis.conf /Redis/redis.conf

# Скрипт generate_domain
COPY scripts /scripts

# entrypoint
COPY entrypoint.sh /entrypoint.sh

# Права
RUN chmod +x /Redis/redis-server /Redis/redis-cli /entrypoint.sh

# ENV для скрипта
ENV DOMAIN_DIR=/server_data

# На всякий случай создадим директорию
RUN mkdir -p /server_data

ARG PROMETHEUS_VERSION=2.51.1

RUN cd /tmp && \
    wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && \
    tar xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && \
    mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/prometheus && \
    rm -rf /tmp/prometheus*

# Папка для конфигов Prometheus внутри контейнера
RUN mkdir -p /configs /etc/prometheus/data

# Кладём наш конфиг в /configs
COPY configs /configs

# --- Redis, скрипты, entrypoint как раньше ---
WORKDIR /Redis
COPY --from=builder /build/redis/src/redis-server /Redis/redis-server
COPY --from=builder /build/redis/src/redis-cli    /Redis/redis-cli
COPY redis.conf /Redis/redis.conf
COPY scripts /scripts
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /Redis/redis-server /Redis/redis-cli /entrypoint.sh

ENV DOMAIN_DIR=/server_data
RUN mkdir -p /server_data

EXPOSE 6379 9090

CMD ["/entrypoint.sh"]
