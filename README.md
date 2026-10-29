# GorkyCodeTest-Database

PostgreSQL 17 с расширением [pgvector](https://github.com/pgvector/pgvector) —
хранилище пользователей, задач и встреч, а также заданий планировщика
`Notifications`. Образ собирается на `pgvector/pgvector:pg17`, схема создаётся
из [init.sql](init.sql).

Контейнер называется `tasks_postgres_db`; порт по умолчанию — `5432`.

## Запуск

Из корня репозитория (рекомендуется; сеть `app-network` объявлена как external):

```bash
docker network create app-network 2>/dev/null || true
docker compose up -d postgres
```

Или только этот модуль — тогда общая сеть должна существовать заранее:

```bash
docker network create app-network
docker compose up -d --build
```

`init.sql` копируется в `/docker-entrypoint-initdb.d/01-init.sql` и выполняется
**один раз — при инициализации пустого каталога данных**. При последующих
запусках изменения в `init.sql` не применяются: нужна миграция либо пересоздание
тома `postgres_data` (`docker compose down -v` — уничтожит данные).

## Переменные окружения

Файл `.env` лежит рядом с compose-файлом (шаблон — [.env.example](.env.example)):

| Переменная | По умолчанию | Назначение |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | — (обязательна) | Пароль пользователя БД; без него compose не стартует |
| `POSTGRES_USER` | `postgres` | Пользователь БД |
| `POSTGRES_DB` | `tasks_db` | Имя базы |
| `POSTGRES_PORT` | `5432` | Порт на хосте |

Healthcheck (`pg_isready`) позволяет `Notifications` ждать готовности БД через
`depends_on: condition: service_healthy`.

## Схема

```
"user"                       tasks                              done_tasks
├── user_id BIGINT PK        ├── task_id BIGSERIAL PK           ├── query_id UUID PK
├── username TEXT            ├── user_id → "user" (CASCADE)     └── created_at TIMESTAMP
└── timezone TEXT            ├── type event_type
                             ├── title TEXT
                             ├── title_vector vector(768)
                             ├── date DATE
                             ├── date_notify TIMESTAMPTZ
                             ├── raw_text TEXT
                             ├── time TIME
                             └── is_notified BOOLEAN
```

* `"user"` — имя в кавычках, потому что `user` зарезервировано в PostgreSQL.
  `user_id` — идентификатор ВК, задаётся извне (не `SERIAL`). Часовой пояс по
  умолчанию `Europe/Moscow`.
* `event_type` — ENUM `('task', 'meeting')`, строго ограничивает тип события.
* `tasks.title` — короткая формулировка без даты, `raw_text` — исходное
  сообщение пользователя. `title_vector` — нормализованный эмбеддинг заголовка,
  размерность **обязана** совпадать с `EMBEDDING_DIMENSION` в бэкенде (768,
  модель `paraphrase-multilingual-mpnet-base-v2`).
* `tasks.date` — дата события (`NOT NULL`), `time` — необязательное время,
  `date_notify` — момент напоминания (UTC), `is_notified` — отправлено ли оно.
* `done_tasks` — обработанные запросы API по `query_id` из заголовка
  `X-Request-ID`; первичный ключ отсекает повторы, `created_at` заполняется
  сервером.

### Индексы

| Индекс | Назначение |
| --- | --- |
| `idx_tasks_user_date` | выборка задач пользователя по дате |
| `idx_tasks_date_notify` | частичный (`WHERE date_notify IS NOT NULL`) — для фоновой обработки напоминаний |
| `idx_tasks_title_vector_hnsw` | HNSW по `title_vector vector_cosine_ops` — семантический поиск |

## Подключение и проверка

```bash
# из контейнера
docker exec -it tasks_postgres_db psql -U postgres -d tasks_db

# с хоста
psql "postgresql://postgres:<пароль>@localhost:5432/tasks_db"
```

```sql
\dt                                     -- таблицы
SELECT extname FROM pg_extension;       -- vector
SELECT user_id, title, date, time, date_notify FROM tasks ORDER BY task_id DESC LIMIT 10;
```

Проверка векторного поиска (запрос — любой вектор размерности 768):

```sql
SELECT task_id, title, title_vector <=> '[0.1, 0.2, ...]'::vector AS distance
FROM tasks
WHERE user_id = 1 AND title_vector IS NOT NULL
ORDER BY distance
LIMIT 5;
```

Строка подключения для бэкенда:

```
postgresql+psycopg://postgres:<пароль>@postgres:5432/tasks_db
```

(имя `postgres` — это имя сервиса в общей сети `app-network`; при локальном
запуске бэкенда используйте `localhost`).

## Замечания

* База не содержит миграций: изменения схемы вносятся в `init.sql` для новых
  установок и отдельным `ALTER`/миграцией для существующих.
* Том `postgres_data` — единственное место хранения данных; при удалении тома
  задачи, пользователи и запланированные напоминания пропадают.
* Время в контейнере — UTC (`ENV TZ=UTC`), моменты напоминаний хранятся с
  часовым поясом.
