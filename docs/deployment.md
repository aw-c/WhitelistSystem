# Развёртывание WhitelistSystem на сервере через Docker

## Управление сервисом через скрипты

В директории `scripts/` находятся bash-скрипты для полного жизненного цикла сервиса.
Все скрипты требуют запуска от `root` (`sudo`).

| Скрипт | Назначение |
|---|---|
| `setup.sh` | Первоначальная настройка: установка зависимостей, TLS, htpasswd, Nginx, запуск контейнеров |
| `start.sh` | Запуск остановленных контейнеров |
| `stop.sh` | Остановка контейнеров |
| `restart.sh` | Перезапуск контейнеров |
| `heartbeat.sh` | Проверка работоспособности всех компонентов |

### Первый запуск

```bash
cd /opt/whitelist-system
sudo bash scripts/setup.sh
```

`setup.sh` сам проверит и установит все недостающие зависимости:
- **Docker** и **Docker Compose plugin** — если не установлены
- **Nginx** — если не установлен
- **apache2-utils** (htpasswd) — если не установлен
- **postgresql-client** (psql) — если не установлен

Затем создаст `.env`, TLS-сертификат, `.htpasswd`, конфигурацию Nginx и запустит контейнеры.

### Обычное управление

```bash
# Запуск
sudo bash scripts/start.sh

# Запуск с пересборкой образа (после изменений кода)
sudo bash scripts/start.sh --build

# Остановка (данные сохраняются)
sudo bash scripts/stop.sh

# Остановка с удалением данных БД (НЕОБРАТИМО)
sudo bash scripts/stop.sh --volumes

# Перезапуск
sudo bash scripts/restart.sh

# Перезапуск с пересборкой образа
sudo bash scripts/restart.sh --build

# Перезапуск с перезагрузкой Nginx
sudo bash scripts/restart.sh --nginx
```

### Heartbeat — проверка состояния

```bash
# Однократная проверка
sudo bash scripts/heartbeat.sh

# Циклическая проверка каждые 30 секунд
sudo bash scripts/heartbeat.sh --watch 30

# Только код выхода (0 = OK, >0 = есть проблемы), без вывода
sudo bash scripts/heartbeat.sh --quiet
```

Heartbeat проверяет:
- Статус Docker-контейнеров (`app`, `db`)
- Доступность PostgreSQL (`pg_isready` внутри контейнера, либо `psql` на хосте)
- HTTP-ответ приложения на `GET /api/steam-ids`
- Статус Nginx и прослушивание порта 443

Код выхода `0` означает, что все проверки пройдены. Любое ненулевое значение равно
количеству провалившихся проверок — удобно для мониторинга через cron или systemd.

---

## Требования

| Инструмент | Минимальная версия |
|---|---|
| Docker Engine | 24+ |
| Docker Compose plugin | 2.20+ |

Убедиться, что оба установлены:
```bash
docker version
docker compose version
```

---

## Структура файлов

```
WhitelistSystem/
├── Dockerfile            # образ приложения
├── docker-compose.yml    # оркестрация app + postgres
├── .env.example          # шаблон переменных окружения
└── docs/
    └── deployment.md     # этот файл
```

---

## Шаги развёртывания

### 1. Скопировать репозиторий на сервер

```bash
git clone <your-repo-url> /opt/whitelist-system
cd /opt/whitelist-system
```

Или передать файлы через `scp` / `rsync`:
```bash
rsync -avz --exclude bin --exclude obj ./ user@your-server:/opt/whitelist-system/
```

---

### 2. Создать файл `.env`

```bash
cp .env.example .env
nano .env          # или vim, gedit и т. д.
```

Заполнить **обязательно**:
```
DB_PASSWORD=надёжный_пароль
```

Остальные параметры можно оставить по умолчанию.

> `.env` содержит пароль — **не добавляйте его в git**.  
> Добавьте `.env` в `.gitignore`, если ещё не добавлено.

---

### 3. Сборка и запуск

```bash
docker compose up -d --build
```

Флаг `--build` заставляет Docker пересобрать образ приложения.  
Флаг `-d` запускает контейнеры в фоне.

Проверить, что оба контейнера поднялись:
```bash
docker compose ps
```

Ожидаемый вывод:
```
NAME                    STATUS          PORTS
whitelistsystem-db-1    Up (healthy)    5432/tcp
whitelistsystem-app-1   Up              0.0.0.0:8080->8080/tcp
```

---

### 4. Первый запуск — создание таблицы

Приложение вызывает `EnsureCreated()` при старте — таблица `steam_whitelist_entries`
создаётся автоматически, если её нет.

Убедиться, что таблица создана:
```bash
docker compose exec db psql -U postgres -d whitelist_system -c "\dt"
```

---

### 5. Проверка работы

Открыть в браузере: `http://your-server-ip:8080`

Или через curl:
```bash
# Получить все записи
curl http://your-server-ip:8080/api/steam-ids

# Добавить запись
curl -X POST http://your-server-ip:8080/api/steam-ids \
     -H "Content-Type: application/json" \
     -d '{"steamId": "76561198000000001", "comment": "test"}'

# Проверить наличие конкретного SteamId
curl http://your-server-ip:8080/api/steam-ids/76561198000000001

# Удалить запись
curl -X DELETE http://your-server-ip:8080/api/steam-ids/76561198000000001
```

---

## Обновление приложения

После изменения кода:
```bash
git pull                           # получить новую версию
docker compose up -d --build app   # пересобрать только контейнер приложения
```

PostgreSQL при этом не перезапускается, данные сохраняются в volume `pg_data`.

---

## Просмотр логов

```bash
# Все контейнеры
docker compose logs -f

# Только приложение
docker compose logs -f app

# Только БД
docker compose logs -f db
```

---

## Остановка и удаление

```bash
# Остановить без удаления данных
docker compose down

# Остановить и удалить volume с данными БД (ОСТОРОЖНО — данные потеряются)
docker compose down -v
```

---

## Настройка Nginx (reverse proxy)

### Обзор схемы доступа

| Путь | Метод | Basic Auth |
|---|---|---|
| `/` и все остальные маршруты | любой | **обязателен** |
| `GET /api/steam-ids` | GET | не требуется |
| `GET /api/steam-ids/{steamId}` | GET | не требуется |
| `POST /api/steam-ids` | POST | **обязателен** |
| `DELETE /api/steam-ids/{steamId}` | DELETE | **обязателен** |

Всё это реализуется только средствами Nginx — код приложения не изменяется.

---

### 1. Установка Nginx

```bash
sudo apt update
sudo apt install -y nginx
```

---

### 2. Создание файла паролей (.htpasswd)

Установить утилиту `htpasswd` (входит в пакет `apache2-utils`):

```bash
sudo apt install -y apache2-utils
```

Создать файл и добавить пользователя (замените `admin` на нужное имя):

```bash
sudo htpasswd -c /etc/nginx/.htpasswd admin
```

Команда запросит пароль дважды. Для добавления дополнительных пользователей
(без флага `-c`, чтобы не перезаписать файл):

```bash
sudo htpasswd /etc/nginx/.htpasswd другой_пользователь
```

Убедиться, что файл доступен только nginx:

```bash
sudo chmod 640 /etc/nginx/.htpasswd
sudo chown root:www-data /etc/nginx/.htpasswd
```

---

### 3. Самоподписанный TLS-сертификат (без домена)

Создать директорию и сгенерировать ключ + сертификат сроком на 10 лет:

```bash
sudo mkdir -p /etc/nginx/ssl

sudo openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/selfsigned.key \
    -out    /etc/nginx/ssl/selfsigned.crt \
    -subj   "/C=RU/ST=./L=./O=WhitelistSystem/CN=localhost"
```

> Поле `CN=localhost` можно заменить на IP-адрес сервера — браузер/клиент всё равно
> покажет предупреждение, так как сертификат не подписан доверенным УЦ.

Ограничить права на закрытый ключ:

```bash
sudo chmod 600 /etc/nginx/ssl/selfsigned.key
sudo chown root:root /etc/nginx/ssl/selfsigned.key
```

---

### 4. Конфигурационный файл Nginx

Создать файл `/etc/nginx/sites-available/whitelist-system`:

```nginx
# Перенаправление HTTP → HTTPS
server {
    listen 80;
    server_name _;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name _;   # принимаем запросы без привязки к домену

    ssl_certificate     /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # ──────────────────────────────────────────────────────────────
    # GET /api/steam-ids  — публичный
    # POST /api/steam-ids — только с Basic Auth
    # ──────────────────────────────────────────────────────────────
    location = /api/steam-ids {
        # limit_except перечисляет методы БЕЗ ограничений;
        # для всех остальных методов (POST, DELETE, PUT, …) применяются
        # указанные внутри директивы.
        limit_except GET {
            auth_basic           "Restricted";
            auth_basic_user_file /etc/nginx/.htpasswd;
        }

        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       $host;
        proxy_cache_bypass $http_upgrade;
    }

    # ──────────────────────────────────────────────────────────────
    # GET /api/steam-ids/{steamId}    — публичный
    # DELETE /api/steam-ids/{steamId} — только с Basic Auth
    # ──────────────────────────────────────────────────────────────
    location ~ ^/api/steam-ids/.+ {
        limit_except GET {
            auth_basic           "Restricted";
            auth_basic_user_file /etc/nginx/.htpasswd;
        }

        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       $host;
        proxy_cache_bypass $http_upgrade;
    }

    # ──────────────────────────────────────────────────────────────
    # Все остальные маршруты (UI, другие API) — только с Basic Auth
    # ──────────────────────────────────────────────────────────────
    location / {
        auth_basic           "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

> Blazor Server использует WebSocket (`Upgrade: websocket`) — директивы `Upgrade` и
> `Connection upgrade` обязательны, иначе интерактивность сломается.

---

### 5. Включить конфигурацию и перезапустить Nginx

```bash
# Создать символическую ссылку в sites-enabled
sudo ln -s /etc/nginx/sites-available/whitelist-system \
           /etc/nginx/sites-enabled/whitelist-system

# Если конфиг по умолчанию мешает — отключить его
sudo rm -f /etc/nginx/sites-enabled/default

# Проверить синтаксис
sudo nginx -t

# Применить
sudo systemctl reload nginx
```

---

### 6. Проверка

```bash
SERVER=https://your-server-ip

# GET — без авторизации, должен вернуть 200
curl -k "$SERVER/api/steam-ids"

# GET конкретного ID — без авторизации, должен вернуть 200 или 404
curl -k "$SERVER/api/steam-ids/76561198000000001"

# POST — без авторизации, должен вернуть 401
curl -k -X POST "$SERVER/api/steam-ids" \
     -H "Content-Type: application/json" \
     -d '{"steamId":"76561198000000001"}'

# POST — с авторизацией, должен вернуть 201
curl -k -X POST "$SERVER/api/steam-ids" \
     -u admin:ваш_пароль \
     -H "Content-Type: application/json" \
     -d '{"steamId":"76561198000000001"}'

# DELETE — с авторизацией, должен вернуть 204
curl -k -X DELETE "$SERVER/api/steam-ids/76561198000000001" \
     -u admin:ваш_пароль

# UI — без авторизации, должен вернуть 401
curl -k -o /dev/null -w "%{http_code}" "$SERVER/"
```

> Флаг `-k` отключает проверку сертификата — необходимо при использовании
> самоподписанного сертификата.

---

### Примечание о безопасности

Basic Authorization передаёт учётные данные в base64-кодировке, что **не является
шифрованием**. Без TLS пароль можно перехватить. Поэтому использование HTTPS
(пусть даже с самоподписанным сертификатом) обязательно при включённой Basic Auth.

---

## Переменные окружения приложения

| Переменная | Описание | Пример |
|---|---|---|
| `ConnectionStrings__WhitelistDb` | Строка подключения к PostgreSQL | `Host=db;Port=5432;...` |
| `ASPNETCORE_ENVIRONMENT` | Режим работы ASP.NET Core | `Production` |
| `ASPNETCORE_URLS` | Адрес прослушивания | `http://+:8080` |

Переменные передаются через секцию `environment` в `docker-compose.yml`
и автоматически подставляются из `.env`.
