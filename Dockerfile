# Официальный образ PostgreSQL 17 с предустановленным расширением pgvector (для title_vector / RAG)
FROM pgvector/pgvector:pg17

# Устанавливаем локаль и часовой пояс по умолчанию (UTC для корректной работы абсолютных дат)
ENV TZ=UTC

# Копируем SQL-скрипт инициализации.
# Все .sql файлы в /docker-entrypoint-initdb.d/ автоматически выполняются при первом создании БД.
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql
