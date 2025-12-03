# =========================
# СЛОЙ 1: сборка Redis из исходников
# =========================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libjemalloc-dev \
    ca-certificates \
    curl \
    tar \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Клонируем официальный Redis
RUN git clone https://github.com/redis/redis.git
WORKDIR /build/redis

# При желании можно зафиксироваться на версии:
# RUN git checkout 7.4.0

# Собираем Redis
RUN make -j"$(nproc)"


# =========================
# СЛОЙ 2: финальный образ
# =========================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Runtime-зависимости: Python, curl, jemalloc и т.п.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    bash \
    curl \
    python3 \
    python3-requests \
    tar \
    gzip \
    libjemalloc2 \
 && rm -rf /var/lib/apt/lists/*

# ----- Установка lego (как у тебя, только безопаснее) -----
ARG LEGO_VERSION=4.19.2
RUN curl -L -o /tmp/lego.tar.gz "https://github.com/go-acme/lego/releases/download/v${LEGO_VERSION}/lego_v${LEGO_VERSION}_linux_amd64.tar.gz" \
 && tar -xzf /tmp/lego.tar.gz -C /usr/local/bin lego \
 && chmod +x /usr/local/bin/lego \
 && rm -f /tmp/lego.tar.gz

# ----- Установка Prometheus -----
ARG PROMETHEUS_VERSION=2.51.1
RUN curl -L -o /tmp/prometheus.tar.gz "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" \
 && tar -xzf /tmp/prometheus.tar.gz -C /tmp \
 && mv /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/prometheus \
 && rm -rf /tmp/prometheus.tar.gz /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64

# ----- Каталоги под данные и конфиги -----
RUN mkdir -p \
    /Redis \
    /server_data \
    /data/lego \
    /opt/ssl \
    /etc/prometheus/data \
    /configs

# ----- Redis -----
WORKDIR /Redis
COPY --from=builder /build/redis/src/redis-server /Redis/redis-server
COPY --from=builder /build/redis/src/redis-cli    /Redis/redis-cli
COPY redis.conf /Redis/redis.conf

# ----- Скрипты и конфиги -----
COPY scripts /scripts
COPY configs /configs
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /Redis/redis-server /Redis/redis-cli /entrypoint.sh

# ----- ENV -----
ENV DOMAIN_DIR=/server_data

# ----- Порты -----
EXPOSE 6379 9090

# ----- Старт -----
CMD ["/entrypoint.sh"]
