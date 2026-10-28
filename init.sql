-- Схема соответствует ORM-моделям из GorkyCodeTest-Backend (src/database/models.py)

-- Включаем расширение pgvector для хранения эмбеддингов и RAG-поиска
CREATE EXTENSION IF NOT EXISTS vector;

-- Таблица пользователей
-- Имя "user" взято в двойные кавычки, так как user — зарезервированное слово в PostgreSQL
CREATE TABLE IF NOT EXISTS "user" (
    -- ID пользователя во ВКонтакте (задаётся извне, поэтому не BIGSERIAL)
    user_id BIGINT PRIMARY KEY,

    -- Имя и фамилия
    username TEXT NOT NULL,

    -- Часовой пояс (например, 'Europe/Moscow' или 'UTC+3')
    timezone TEXT NOT NULL DEFAULT 'Europe/Moscow'
);

-- Перечисление (ENUM) для строгого ограничения типа события
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_type') THEN
        CREATE TYPE event_type AS ENUM ('task', 'meeting');
    END IF;
END$$;

-- Основная таблица задач и встреч
CREATE TABLE IF NOT EXISTS tasks (
    -- ID самой задачи
    task_id BIGSERIAL PRIMARY KEY,

    -- ID человека из таблицы "user" для связи таблиц
    user_id BIGINT NOT NULL REFERENCES "user"(user_id) ON DELETE CASCADE,

    -- Тип события: 'task' или 'meeting'
    type event_type NOT NULL,

    -- Краткая выжимка из raw_text без даты
    title TEXT NOT NULL,

    -- Эмбеддинг для RAG. Размерность должна совпадать с EMBEDDING_DIMENSION в ORM (768)
    title_vector vector(768),

    -- Дата события
    date DATE NOT NULL,

    -- Время и дата, когда нужно напомнить о событии
    date_notify TIMESTAMPTZ,

    -- Изначальное сырое сообщение пользователя
    raw_text TEXT NOT NULL,

    -- Время события (если указано)
    time TIME,

    -- Отправлено ли уже напоминание
    is_notified BOOLEAN DEFAULT false
);

-- Индекс для быстрой выборки задач конкретного пользователя по дате
CREATE INDEX IF NOT EXISTS idx_tasks_user_date
    ON tasks (user_id, date);

-- Частичный индекс для фонового воркера напоминаний
CREATE INDEX IF NOT EXISTS idx_tasks_date_notify
    ON tasks (date_notify)
    WHERE date_notify IS NOT NULL;

-- HNSW-индекс для быстрого векторного поиска по косинусному сходству (RAG)
CREATE INDEX IF NOT EXISTS idx_tasks_title_vector_hnsw
    ON tasks USING hnsw (title_vector vector_cosine_ops);

-- Выполненные запросы к API: по query_id (UUID4 из X-Request-ID) отсекаются повторы
CREATE TABLE IF NOT EXISTS done_tasks (
    query_id UUID NOT NULL,

    -- Когда запрос был выполнен
    created_at TIMESTAMP DEFAULT now() NOT NULL,

    CONSTRAINT done_tasks_pk PRIMARY KEY (query_id)
);
