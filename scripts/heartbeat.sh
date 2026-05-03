#!/usr/bin/env bash
# =============================================================================
# heartbeat.sh — проверка работоспособности WhitelistSystem
#
# Выполняет следующие проверки:
#   1. Docker-контейнеры запущены и здоровы
#   2. PostgreSQL отвечает (через psql или pg_isready внутри контейнера)
#   3. Приложение отвечает на GET /api/steam-ids (HTTP 200)
#   4. Nginx запущен и принимает соединения
#
# Коды выхода:
#   0 — все проверки пройдены
#   1 — одна или более проверок провалились
#
# Использование:
#   ./heartbeat.sh              # однократная проверка
#   ./heartbeat.sh --watch 30  # циклическая проверка каждые 30 секунд
#   ./heartbeat.sh --quiet     # только код выхода, без вывода
# =============================================================================
set -uo pipefail

# ─── цвета ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ─── параметры ───────────────────────────────────────────────────────────────
APP_PORT="${APP_PORT:-8080}"
WATCH_INTERVAL=0   # 0 = однократно
QUIET=false
FAIL_COUNT=0

# ─── парсинг аргументов ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch)
            WATCH_INTERVAL="${2:?'--watch требует значение (секунды)'}"
            shift 2 ;;
        --quiet) QUIET=true; shift ;;
        *) shift ;;
    esac
done

# ─── вывод ───────────────────────────────────────────────────────────────────
log()  { $QUIET || echo -e "$*"; }
ok()   { log "${GREEN}  ✓${NC} $*"; }
fail() { log "${RED}  ✗${NC} $*"; (( FAIL_COUNT++ )) || true; }
warn() { log "${YELLOW}  !${NC} $*"; }
info() { log "${CYAN}$*${NC}"; }

# =============================================================================
# Проверки
# =============================================================================

check_docker_containers() {
    info "── Docker-контейнеры ──────────────────────────────────────"
    cd "$PROJECT_DIR"

    if ! command -v docker &>/dev/null; then
        fail "Docker не установлен"
        return
    fi

    local services=("app" "db")
    for svc in "${services[@]}"; do
        local state
        state=$(docker compose ps --format '{{.State}}' "$svc" 2>/dev/null || echo "")
        if [[ "$state" == "running" ]]; then
            ok "Контейнер '$svc': running"
        elif [[ -z "$state" ]]; then
            fail "Контейнер '$svc': не найден"
        else
            fail "Контейнер '$svc': $state"
        fi
    done
}

check_postgres() {
    info "── PostgreSQL ─────────────────────────────────────────────"
    cd "$PROJECT_DIR"

    # Пробуем pg_isready внутри контейнера db
    if docker compose exec -T db pg_isready -U postgres -q 2>/dev/null; then
        ok "PostgreSQL: принимает соединения"
    else
        # Резервно: проверяем через psql, если он установлен на хосте
        if command -v psql &>/dev/null; then
            local db_user db_pass db_name
            db_user=$(grep -E '^DB_USER=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "postgres")
            db_name=$(grep -E '^DB_NAME=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "whitelist_system")
            db_pass=$(grep -E '^DB_PASSWORD=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "")

            if PGPASSWORD="$db_pass" psql -h 127.0.0.1 -U "$db_user" -d "$db_name" -c "SELECT 1" -q &>/dev/null; then
                ok "PostgreSQL: соединение через psql (localhost) успешно"
            else
                fail "PostgreSQL: не отвечает ни через контейнер, ни через localhost"
            fi
        else
            fail "PostgreSQL: pg_isready вернул ошибку; psql на хосте не установлен"
        fi
    fi
}

check_app_http() {
    info "── Приложение (HTTP) ──────────────────────────────────────"

    if ! command -v curl &>/dev/null; then
        warn "curl не установлен — пропускаем HTTP-проверку"
        return
    fi

    local url="http://127.0.0.1:${APP_PORT}/api/steam-ids"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 \
        --retry 0 \
        "$url" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        ok "GET $url → HTTP $http_code"
    elif [[ "$http_code" == "000" ]]; then
        fail "GET $url → нет соединения (таймаут или отказ)"
    else
        fail "GET $url → HTTP $http_code (ожидалось 200)"
    fi
}

check_nginx() {
    info "── Nginx ──────────────────────────────────────────────────"

    if ! command -v nginx &>/dev/null; then
        warn "Nginx не установлен — пропускаем проверку"
        return
    fi

    if systemctl is-active --quiet nginx; then
        ok "Nginx: активен (systemd)"
    else
        fail "Nginx: не запущен"
        return
    fi

    # Проверяем, что 443 порт слушается
    if ss -tlnp 2>/dev/null | grep -q ':443 '; then
        ok "Nginx: порт 443 слушается"
    elif netstat -tlnp 2>/dev/null | grep -q ':443 '; then
        ok "Nginx: порт 443 слушается (netstat)"
    else
        warn "Порт 443 не обнаружен — возможно, Nginx ещё запускается"
    fi
}

# =============================================================================
# Итог
# =============================================================================
print_summary() {
    log ""
    if [[ $FAIL_COUNT -eq 0 ]]; then
        log "${BOLD}${GREEN}Все проверки пройдены.${NC}"
    else
        log "${BOLD}${RED}Провалено проверок: ${FAIL_COUNT}.${NC}"
    fi
    log ""
}

# =============================================================================
# Один прогон
# =============================================================================
run_checks() {
    FAIL_COUNT=0
    log ""
    log "${BOLD}${CYAN}=== WhitelistSystem :: heartbeat [$(date '+%Y-%m-%d %H:%M:%S')] ===${NC}"
    check_docker_containers
    check_postgres
    check_app_http
    check_nginx
    print_summary
}

# =============================================================================
# main
# =============================================================================
if [[ $WATCH_INTERVAL -gt 0 ]]; then
    while true; do
        run_checks
        log "Следующая проверка через ${WATCH_INTERVAL} сек. (Ctrl+C для выхода)…"
        sleep "$WATCH_INTERVAL"
    done
else
    run_checks
    exit $FAIL_COUNT
fi
