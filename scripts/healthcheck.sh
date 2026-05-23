#!/usr/bin/env bash
set -e

curl -fsS http://127.0.0.1:7860/ >/dev/null
curl -fsS http://127.0.0.1:8080/ >/dev/null
curl -fsS http://127.0.0.1:8888/api/status >/dev/null
