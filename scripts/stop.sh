#!/usr/bin/env bash
# =============================================================================
# stop.sh — остановка WhitelistSystem
#
# Флаги:
#   --volumes  — также удалить volume с данными PostgreSQL (НЕОБРАТИМО)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

[[ "$EUID" -ne 0 ]] && error "Запустите скрипт с правами root: sudo $0"

cd "$PROJECT_DIR"

if [[ "${1:-}" == "--volumes" ]]; then
    warn "ВНИМАНИЕ: будут удалены все данные PostgreSQL (volume pg_data)!"
    read -rp "Вы уверены? Введите YES для подтверждения: " confirm
    if [[ "$confirm" != "YES" ]]; then
        info "Отменено."
        exit 0
    fi
    info "Останавливаем контейнеры и удаляем volumes…"
    docker compose down -v
else
    info "Останавливаем контейнеры (данные сохраняются)…"
    docker compose down
fi

info "Контейнеры остановлены."
