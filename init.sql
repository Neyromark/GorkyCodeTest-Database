-- Включаем расширение pgvector для хранения эмбеддингов и RAG-поиска
CREATE EXTENSION IF NOT EXISTS vector;

-- Таблица пользователей
-- Имя "user" взято в двойные кавычки, так как user — зарезервированное слово в PostgreSQL
CREATE TABLE IF NOT EXISTS "user" (
    -- ID пользователя во ВКонтакте
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

    -- Эмбеддинг title для RAG (1536 — стандарт для OpenAI text-embedding-3-small / ada-002).
    -- Поменяйте размерность под вашу модель при необходимости (1024 для BGE-M3/E5-large, 768 для nomic/mpnet, 384 для MiniLM).
    title_vector vector(1536),

    -- Абсолютная дата и время события
    date TIMESTAMPTZ NOT NULL,

    -- Время и дата, когда нужно напомнить о событии
    date_notify TIMESTAMPTZ,

    -- Изначальное сырое сообщение пользователя
    raw_text TEXT NOT NULL
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
