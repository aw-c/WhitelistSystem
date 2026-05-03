#!/usr/bin/env bash
# =============================================================================
# start.sh — запуск WhitelistSystem (без пересборки образа)
#
# Если нужна пересборка — используйте setup.sh или передайте флаг --build:
#   ./start.sh --build
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

[[ "$EUID" -ne 0 ]] && error "Запустите скрипт с правами root: sudo $0"

# ─── проверки ─────────────────────────────────────────────────────────────────
[[ -f "$PROJECT_DIR/.env" ]] || error ".env не найден. Сначала запустите setup.sh"

if ! systemctl is-active --quiet nginx; then
    warn "Nginx не запущен — запускаем…"
    systemctl start nginx
fi

# ─── запуск контейнеров ───────────────────────────────────────────────────────
cd "$PROJECT_DIR"

BUILD_FLAG=""
if [[ "${1:-}" == "--build" ]]; then
    BUILD_FLAG="--build"
    info "Режим сборки: пересборка образа приложения."
fi

info "Запускаем контейнеры…"
docker compose up -d $BUILD_FLAG

info "Статус контейнеров:"
docker compose ps

info "Сервис запущен."
