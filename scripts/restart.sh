#!/usr/bin/env bash
# =============================================================================
# restart.sh — перезапуск WhitelistSystem
#
# Флаги:
#   --build    — пересобрать образ приложения перед запуском
#   --nginx    — также перезагрузить Nginx
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

[[ "$EUID" -ne 0 ]] && error "Запустите скрипт с правами root: sudo $0"

[[ -f "$PROJECT_DIR/.env" ]] || error ".env не найден. Сначала запустите setup.sh"

BUILD_FLAG=""
RELOAD_NGINX=false

for arg in "$@"; do
    case "$arg" in
        --build) BUILD_FLAG="--build" ;;
        --nginx) RELOAD_NGINX=true ;;
    esac
done

cd "$PROJECT_DIR"

info "Останавливаем контейнеры…"
docker compose down

info "Запускаем контейнеры${BUILD_FLAG:+ (с пересборкой)}…"
docker compose up -d $BUILD_FLAG

if $RELOAD_NGINX; then
    if nginx -t 2>/dev/null; then
        info "Перезагружаем Nginx…"
        systemctl reload nginx
    else
        warn "Конфигурация Nginx содержит ошибки — reload пропущен."
        nginx -t
    fi
fi

info "Статус контейнеров:"
docker compose ps

info "Перезапуск завершён."
