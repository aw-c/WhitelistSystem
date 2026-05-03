#!/usr/bin/env bash
# =============================================================================
# setup.sh — первоначальная настройка и запуск WhitelistSystem
#
# Что делает скрипт:
#   1. Проверяет / устанавливает зависимости (Docker, Docker Compose, Nginx,
#      apache2-utils, postgresql-client)
#   2. Создаёт .env из .env.example, если его ещё нет
#   3. Генерирует самоподписанный TLS-сертификат (если ещё нет)
#   4. Создаёт /etc/nginx/.htpasswd (если ещё нет)
#   5. Записывает конфигурацию Nginx
#   6. Собирает и запускает Docker-контейнеры
# =============================================================================
set -euo pipefail

# ─── цвета ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── корень проекта (директория, где лежит docker-compose.yml) ────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ─── параметры (можно переопределить через переменные окружения) ──────────────
NGINX_CONF_NAME="${NGINX_CONF_NAME:-whitelist-system}"
NGINX_HTPASSWD="${NGINX_HTPASSWD:-/etc/nginx/.htpasswd}"
NGINX_SSL_DIR="${NGINX_SSL_DIR:-/etc/nginx/ssl}"
NGINX_CERT="${NGINX_SSL_DIR}/selfsigned.crt"
NGINX_KEY="${NGINX_SSL_DIR}/selfsigned.key"
HTPASSWD_USER="${HTPASSWD_USER:-admin}"
APP_PORT="${APP_PORT:-8080}"
CERT_DAYS="${CERT_DAYS:-3650}"

# ─── root? ────────────────────────────────────────────────────────────────────
[[ "$EUID" -ne 0 ]] && error "Запустите скрипт с правами root: sudo $0"

# =============================================================================
# 1. Вспомогательные функции
# =============================================================================
pkg_installed() { dpkg -s "$1" &>/dev/null; }
cmd_exists()    { command -v "$1" &>/dev/null; }

apt_install() {
    info "Установка пакетов: $*"
    apt-get install -y "$@"
}

ensure_apt_updated() {
    if [[ ! -f /tmp/.apt_updated ]]; then
        info "apt-get update …"
        apt-get update -qq
        touch /tmp/.apt_updated
    fi
}

# =============================================================================
# 2. Docker
# =============================================================================
install_docker() {
    info "Docker не найден — устанавливаем…"
    ensure_apt_updated
    apt_install ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
}

check_docker() {
    if ! cmd_exists docker; then
        install_docker
    else
        info "Docker: $(docker --version)"
    fi

    if ! docker compose version &>/dev/null; then
        ensure_apt_updated
        apt_install docker-compose-plugin
    fi
    info "Docker Compose: $(docker compose version)"
}

# =============================================================================
# 3. Nginx
# =============================================================================
check_nginx() {
    if ! pkg_installed nginx; then
        info "Nginx не найден — устанавливаем…"
        ensure_apt_updated
        apt_install nginx
        systemctl enable nginx
    else
        info "Nginx: $(nginx -v 2>&1)"
    fi
}

# =============================================================================
# 4. apache2-utils (htpasswd)
# =============================================================================
check_htpasswd() {
    if ! cmd_exists htpasswd; then
        info "htpasswd не найден — устанавливаем apache2-utils…"
        ensure_apt_updated
        apt_install apache2-utils
    else
        info "htpasswd: найден"
    fi
}

# =============================================================================
# 5. PostgreSQL-клиент (psql)
# =============================================================================
check_psql() {
    if ! cmd_exists psql; then
        info "psql не найден — устанавливаем postgresql-client…"
        ensure_apt_updated
        # Пробуем актуальный клиент для Ubuntu/Debian
        if apt-get install -y postgresql-client &>/dev/null; then
            info "postgresql-client установлен"
        else
            warn "Не удалось установить postgresql-client через apt. Пропускаем."
        fi
    else
        info "psql: $(psql --version)"
    fi
}

# =============================================================================
# 6. .env
# =============================================================================
setup_env() {
    local env_file="$PROJECT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        info ".env уже существует — пропускаем."
        return
    fi

    if [[ ! -f "$PROJECT_DIR/.env.example" ]]; then
        error "Файл .env.example не найден в $PROJECT_DIR"
    fi

    cp "$PROJECT_DIR/.env.example" "$env_file"
    warn "Создан .env из .env.example."
    warn "Откройте $env_file и задайте DB_PASSWORD перед продолжением."

    read -rp "Введите DB_PASSWORD (или Enter для использования случайного пароля): " db_pass
    if [[ -z "$db_pass" ]]; then
        db_pass="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)"
        info "Сгенерирован случайный пароль DB_PASSWORD."
    fi

    # заменяем значение в .env
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${db_pass}|" "$env_file"
    info ".env настроен."
}

# =============================================================================
# 7. TLS-сертификат
# =============================================================================
setup_tls() {
    if [[ -f "$NGINX_CERT" && -f "$NGINX_KEY" ]]; then
        info "TLS-сертификат уже существует — пропускаем."
        return
    fi

    info "Генерируем самоподписанный TLS-сертификат (${CERT_DAYS} дней)…"
    mkdir -p "$NGINX_SSL_DIR"

    openssl req -x509 -nodes -days "$CERT_DAYS" \
        -newkey rsa:2048 \
        -keyout "$NGINX_KEY" \
        -out    "$NGINX_CERT" \
        -subj   "/C=RU/ST=./L=./O=WhitelistSystem/CN=localhost"

    chmod 600 "$NGINX_KEY"
    chown root:root "$NGINX_KEY"
    info "Сертификат создан: $NGINX_CERT"
}

# =============================================================================
# 8. .htpasswd
# =============================================================================
setup_htpasswd() {
    if [[ -f "$NGINX_HTPASSWD" ]]; then
        info ".htpasswd уже существует — пропускаем."
        return
    fi

    info "Создаём .htpasswd (пользователь: ${HTPASSWD_USER})…"
    # -c создаёт файл; запрашиваем пароль интерактивно
    htpasswd -c "$NGINX_HTPASSWD" "$HTPASSWD_USER"

    chmod 640 "$NGINX_HTPASSWD"
    chown root:www-data "$NGINX_HTPASSWD"
    info ".htpasswd создан."
}

# =============================================================================
# 9. Конфигурация Nginx
# =============================================================================
setup_nginx_conf() {
    local conf_available="/etc/nginx/sites-available/${NGINX_CONF_NAME}"
    local conf_enabled="/etc/nginx/sites-enabled/${NGINX_CONF_NAME}"

    if [[ -f "$conf_available" ]]; then
        info "Конфигурация Nginx уже существует — пропускаем запись файла."
    else
        info "Записываем конфигурацию Nginx: $conf_available"
        cat > "$conf_available" <<NGINX_EOF
# Перенаправление HTTP → HTTPS
server {
    listen 80;
    server_name _;

    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     ${NGINX_CERT};
    ssl_certificate_key ${NGINX_KEY};

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # GET /api/steam-ids  — публичный
    # POST /api/steam-ids — только с Basic Auth
    location = /api/steam-ids {
        limit_except GET {
            auth_basic           "Restricted";
            auth_basic_user_file ${NGINX_HTPASSWD};
        }

        proxy_pass         http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # GET /api/steam-ids/{id}    — публичный
    # DELETE /api/steam-ids/{id} — только с Basic Auth
    location ~ ^/api/steam-ids/.+ {
        limit_except GET {
            auth_basic           "Restricted";
            auth_basic_user_file ${NGINX_HTPASSWD};
        }

        proxy_pass         http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # Все остальные маршруты — только с Basic Auth
    location / {
        auth_basic           "Restricted";
        auth_basic_user_file ${NGINX_HTPASSWD};

        proxy_pass         http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINX_EOF
    fi

    # Включить сайт
    if [[ ! -L "$conf_enabled" ]]; then
        ln -s "$conf_available" "$conf_enabled"
        info "Сайт включён: $conf_enabled"
    fi

    # Отключить default, если мешает
    if [[ -L /etc/nginx/sites-enabled/default ]]; then
        rm /etc/nginx/sites-enabled/default
        warn "Удалена символическая ссылка /etc/nginx/sites-enabled/default"
    fi

    info "Проверяем синтаксис Nginx…"
    nginx -t

    info "Перезагружаем Nginx…"
    systemctl reload nginx
}

# =============================================================================
# 10. Docker Compose — сборка и запуск
# =============================================================================
start_containers() {
    info "Запускаем контейнеры (docker compose up -d --build)…"
    cd "$PROJECT_DIR"
    docker compose up -d --build
    info "Контейнеры запущены."
    docker compose ps
}

# =============================================================================
# main
# =============================================================================
main() {
    info "=== WhitelistSystem :: setup ==="
    info "Директория проекта: $PROJECT_DIR"

    check_docker
    check_nginx
    check_htpasswd
    check_psql
    setup_env
    setup_tls
    setup_htpasswd
    setup_nginx_conf
    start_containers

    info "=== Готово! ==="
    info "Сервис доступен по адресу: https://$(hostname -I | awk '{print $1}')"
}

main "$@"
