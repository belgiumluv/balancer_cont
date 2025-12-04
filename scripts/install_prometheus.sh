#!/usr/bin/env bash
set -e

PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-2.51.1}"
TMP_DIR="$(mktemp -d)"

cd "$TMP_DIR"

echo "Downloading Prometheus v${PROMETHEUS_VERSION}..."
curl -L -o prometheus.tar.gz \
  "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

tar -xzf prometheus.tar.gz
cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64"

# Кладём только бинарник
mv prometheus /usr/local/bin/prometheus
chmod +x /usr/local/bin/prometheus

cd /
rm -rf "$TMP_DIR"

echo "Prometheus installed to /usr/local/bin/prometheus"
prometheus --version || true
