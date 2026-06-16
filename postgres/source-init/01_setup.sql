-- Source Postgres (ERP simulado BanVic)
-- Cria as 6 tabelas transacionais e carrega via COPY dos CSVs montados em /data/

CREATE TABLE IF NOT EXISTS public.agencias (
    cod_agencia     INTEGER PRIMARY KEY,
    nome            TEXT,
    endereco        TEXT,
    cidade          TEXT,
    uf              TEXT,
    data_abertura   DATE,
    tipo_agencia    TEXT
);
COPY public.agencias FROM '/data/agencias.csv' WITH (FORMAT csv, HEADER true);

CREATE TABLE IF NOT EXISTS public.clientes (
    cod_cliente      INTEGER PRIMARY KEY,
    primeiro_nome    TEXT,
    ultimo_nome      TEXT,
    email            TEXT,
    tipo_cliente     TEXT,
    data_inclusao    TIMESTAMP WITH TIME ZONE,
    cpfcnpj          TEXT,
    data_nascimento  DATE,
    endereco         TEXT,
    cep              TEXT
);
COPY public.clientes FROM '/data/clientes.csv' WITH (FORMAT csv, HEADER true);

CREATE TABLE IF NOT EXISTS public.colaboradores (
    cod_colaborador  INTEGER PRIMARY KEY,
    primeiro_nome    TEXT,
    ultimo_nome      TEXT,
    email            TEXT,
    cpf              TEXT,
    data_nascimento  DATE,
    endereco         TEXT,
    cep              TEXT
);
COPY public.colaboradores FROM '/data/colaboradores.csv' WITH (FORMAT csv, HEADER true);

CREATE TABLE IF NOT EXISTS public.colaborador_agencia (
    cod_colaborador  INTEGER,
    cod_agencia      INTEGER,
    PRIMARY KEY (cod_colaborador, cod_agencia)
);
COPY public.colaborador_agencia FROM '/data/colaborador_agencia.csv' WITH (FORMAT csv, HEADER true);

CREATE TABLE IF NOT EXISTS public.contas (
    num_conta                 INTEGER PRIMARY KEY,
    cod_cliente               INTEGER,
    cod_agencia               INTEGER,
    cod_colaborador           INTEGER,
    tipo_conta                TEXT,
    data_abertura             TIMESTAMP WITH TIME ZONE,
    saldo_total               NUMERIC,
    saldo_disponivel          NUMERIC,
    data_ultimo_lancamento    TIMESTAMP WITH TIME ZONE
);
COPY public.contas FROM '/data/contas.csv' WITH (FORMAT csv, HEADER true);

CREATE TABLE IF NOT EXISTS public.propostas_credito (
    cod_proposta            INTEGER PRIMARY KEY,
    cod_cliente             INTEGER,
    cod_colaborador         INTEGER,
    data_entrada_proposta   TIMESTAMP WITH TIME ZONE,
    taxa_juros_mensal       NUMERIC,
    valor_proposta          NUMERIC,
    valor_financiamento     NUMERIC,
    valor_entrada           NUMERIC,
    valor_prestacao         NUMERIC,
    quantidade_parcelas     INTEGER,
    carencia                INTEGER,
    status_proposta         TEXT
);
COPY public.propostas_credito FROM '/data/propostas_credito.csv' WITH (FORMAT csv, HEADER true);
