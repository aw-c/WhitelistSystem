# Развёртывание WhitelistSystem на сервере через Docker

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

## Настройка Nginx (reverse proxy, опционально)

Если на сервере уже стоит Nginx и нужен домен или HTTPS:

```nginx
server {
    listen 80;
    server_name whitelist.example.com;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

> Blazor Server использует WebSocket (`Upgrade: websocket`) — директивы `Upgrade` и
> `Connection upgrade` обязательны, иначе интерактивность сломается.

Для HTTPS — получить сертификат через Certbot:
```bash
certbot --nginx -d whitelist.example.com
```

---

## Переменные окружения приложения

| Переменная | Описание | Пример |
|---|---|---|
| `ConnectionStrings__WhitelistDb` | Строка подключения к PostgreSQL | `Host=db;Port=5432;...` |
| `ASPNETCORE_ENVIRONMENT` | Режим работы ASP.NET Core | `Production` |
| `ASPNETCORE_URLS` | Адрес прослушивания | `http://+:8080` |

Переменные передаются через секцию `environment` в `docker-compose.yml`
и автоматически подставляются из `.env`.
