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

# Клонируем официальный Redis
RUN git clone https://github.com/redis/redis.git

WORKDIR /build/redis

# При желании можно зафиксировать версию:
# RUN git checkout 7.4.0

# Собираем Redis
RUN make -j$(nproc)


# ===== СЛОЙ 2: финальный минимальный образ =====
FROM alpine:3.19

# Только runtime-зависимости
RUN apk add --no-cache \
    jemalloc \
    bash

# Папка Redis внутри контейнера
WORKDIR /Redis

# Копируем бинарники из builder-слоя
COPY --from=builder /build/redis/src/redis-server /Redis/redis-server
COPY --from=builder /build/redis/src/redis-cli    /Redis/redis-cli

# Копируем ТВОЙ внешний конфиг в контейнер
COPY redis.conf /Redis/redis.conf

# На всякий случай сделаем бинарники исполняемыми
RUN chmod +x /Redis/redis-server /Redis/redis-cli

EXPOSE 6379

# Запуск Redis с внешним конфигом
CMD ["/Redis/redis-server", "/Redis/redis.conf"]
