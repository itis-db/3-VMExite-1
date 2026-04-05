CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- схема данных
CREATE TABLE account (
                         account_id BIGSERIAL PRIMARY KEY,
                         username VARCHAR(20) NOT NULL,
                         email VARCHAR(100) NOT NULL UNIQUE,
                         bio VARCHAR(200),
                         password_hash VARCHAR(100) NOT NULL,
                         avatar_url VARCHAR(255),
                         status VARCHAR(20) NOT NULL,
                         role VARCHAR(20) NOT NULL,
                         is_active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE chat (
                      chat_id BIGSERIAL PRIMARY KEY,
                      type VARCHAR(20) NOT NULL,
                      unique_name VARCHAR(50) NOT NULL UNIQUE,
                      title VARCHAR(50) NOT NULL,
                      description VARCHAR(100),
                      is_visible BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE TABLE message (
                         message_id BIGSERIAL PRIMARY KEY,
                         chat_id BIGINT NOT NULL,
                         sender_id BIGINT NOT NULL,
                         content VARCHAR(1000) NOT NULL,
                         created_at TIMESTAMP NOT NULL,
                         is_edited BOOLEAN NOT NULL DEFAULT FALSE,
                         is_deleted BOOLEAN NOT NULL DEFAULT FALSE,

                         CONSTRAINT fk_message_chat
                             FOREIGN KEY (chat_id) REFERENCES chat(chat_id) ON DELETE CASCADE,

                         CONSTRAINT fk_message_account
                             FOREIGN KEY (sender_id) REFERENCES account(account_id) ON DELETE CASCADE
);
CREATE INDEX idx_message_chat_id ON message(chat_id);
CREATE INDEX idx_message_sender_id ON message(sender_id);

-- полнотекстовый поиск
ALTER TABLE message ADD COLUMN search_vector tsvector;

UPDATE message
SET search_vector = to_tsvector('russian', content);

CREATE INDEX idx_message_search
    ON message USING GIN(search_vector);

ALTER TABLE chat ADD COLUMN search_vector tsvector;

UPDATE chat
SET search_vector =
        to_tsvector('russian', coalesce(title, '') || ' ' || coalesce(description, ''));

CREATE INDEX idx_chat_search
    ON chat USING GIN(search_vector);



CREATE FUNCTION message_search_trigger() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
            to_tsvector('russian', NEW.content);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER message_tsvector_update
    BEFORE INSERT OR UPDATE ON message
    FOR EACH ROW EXECUTE FUNCTION message_search_trigger();

CREATE FUNCTION chat_search_trigger() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
            to_tsvector(
                    'russian',
                    coalesce(NEW.title, '') || ' ' || coalesce(NEW.description, '')
            );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER chat_tsvector_update
    BEFORE INSERT OR UPDATE ON chat
    FOR EACH ROW EXECUTE FUNCTION chat_search_trigger();

-- частичный поиск
CREATE INDEX idx_message_content_trgm
    ON message USING GIN (content gin_trgm_ops);

CREATE INDEX idx_chat_title_trgm
    ON chat USING GIN (title gin_trgm_ops);

-- тестовые данные
INSERT INTO account (username, email, password_hash, status, role, is_active)
VALUES
    ('ivan', 'ivan@mail.ru', 'hash1', 'ACTIVE', 'USER', true),
    ('anna', 'anna@mail.ru', 'hash2', 'ACTIVE', 'USER', true);

INSERT INTO chat (type, unique_name, title, description, is_visible)
VALUES
    ('GROUP', 'dev_chat', 'Чат разработчиков', 'Обсуждение программирования', true),
    ('GROUP', 'db_chat', 'Чат баз данных', 'PostgreSQL и поиск', true);

INSERT INTO message (chat_id, sender_id, content, created_at)
VALUES
    (1, 1, 'привет', NOW()),
    (1, 2, 'поиск работает?', NOW()),
    (2, 1, 'привет мир', NOW()),
    (2, 2, 'поиск по частям', NOW());

-- запросы
SELECT *,
       ts_rank(search_vector, plainto_tsquery('russian', 'поиск текста')) AS rank
FROM message
WHERE search_vector @@ plainto_tsquery('russian', 'поиск текста')
ORDER BY rank DESC;

SELECT *,
       similarity(content, 'поиск') AS sim
FROM message
WHERE similarity(content, 'поиск') > 0.3
ORDER BY sim DESC;

SELECT *,
       ts_rank(search_vector, plainto_tsquery('russian', 'поиск')) +
       similarity(content, 'поиск') AS rank
FROM message
WHERE search_vector @@ plainto_tsquery('russian', 'поиск')
   OR similarity(content, 'поиск') > 0.3
ORDER BY rank DESC;