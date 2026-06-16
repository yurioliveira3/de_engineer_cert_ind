# Fase 1 - Core / Foundation

> **Meta da fase:** construir e amarrar o **núcleo obrigatório** do rubric - infraestrutura
> (Docker + Kubernetes), ingestão com **Meltano**, orquestração **Airflow** (sensores,
> retries, idempotência) e **gerenciamento de segredos**. Ao final desta fase, o pipeline
> roda fim-a-fim: fonte -> Meltano -> DW -> dbt, orquestrado por uma DAG, tanto em
> docker-compose quanto em Kind.

**Critério de saída da fase:** `make up` (compose) e `make kind-up` (Kubernetes) sobem o
ambiente; a DAG `banvic_elt` executa verde; os dados das 7 tabelas chegam ao schema `raw`
do DW; nenhuma credencial aparece em código.

---

## F1-01 - Higienizar e definir a estrutura canônica do repositório

**Descrição.** Consolidar as duas árvores (raiz + `Dados - Banvic/banvic`) numa estrutura
única. Remover artefatos que não devem ser versionados.

**Ações.**
- Mover a DAG de referência para `dags/` na raiz (será reescrita em F1-05).
- Extrair os 7 CSVs e `transacoes.csv` para um local de seed (ver F1-02); **não** versionar
  os CSVs grandes.
- Remover do versionamento: `__pycache__/`, `logs/` do template, `data/2025-*/`, `.pyc`.
- Definir a estrutura-alvo:
  ```
  ├── dags/                 # DAGs do Airflow
  ├── meltano/              # projeto Meltano (meltano.yml, plugins)
  ├── dbt_project/          # (existente)
  ├── postgres/             # init do source DB e do DW
  ├── k8s/                  # manifests/Helm values do Kind
  ├── docker/               # Dockerfiles (airflow+meltano, etc.)
  ├── docs/                 # este plano + diagramas
  ├── docker-compose.yml    # ambiente de dev
  ├── Makefile              # bootstrap (compose + kind)
  └── README.md
  ```

**Arquivos afetados.** `.gitignore`, estrutura de pastas, remoção de `Dados - Banvic/banvic/{logs,__pycache__,data}`.

**Critério de aceite.** `git status` limpo de artefatos; árvore espelha a estrutura-alvo;
nenhum `.pyc`/log versionado.

**Dependências.** -

---

## F1-02 - Obter e seedar os dados-fonte (7 tabelas)

**Descrição.** A ingestão precisa de fontes reais. O case define **2 origens**: um banco
transacional (ERP simulado) com 6 tabelas relacionais e o arquivo **`transacoes.csv`**
(grande, ~4 MB) como arquivo on-premise.

**Ações.**
- Documentar a origem dos dados (link do Google Drive em `Descrição dos dados`) e baixar
  o `banvic_data.zip` (7 CSVs).
- **Source Postgres**: criar `postgres/source-init/` que cria o DB `banvic` (schema
  `public`) e carrega via `COPY` as 6 tabelas: `agencias`, `clientes`, `colaboradores`,
  `colaborador_agencia`, `contas`, `propostas_credito`.
- **Arquivo CSV**: posicionar `transacoes.csv` num volume montado para o Meltano/Airflow
  (`data/landing/transacoes.csv`), simulando o arquivo legado.
- Manter os CSVs fora do Git; documentar o passo de obtenção no README.

**Arquivos afetados.** `postgres/source-init/*.sql`, `data/landing/`, `.gitignore`, README (passo de seed).

**Critério de aceite.** Source Postgres sobe com as 6 tabelas populadas
(`SELECT count(*)` > 0 em cada); `transacoes.csv` disponível no caminho de landing.

**Dependências.** F1-01.

---

## F1-03 - Unificar o ambiente em um docker-compose coeso

**Descrição.** Um único `docker-compose.yml` (dev) com todos os serviços, portas sem
conflito e credenciais via `.env`.

**Serviços.**
| Serviço | Papel | Porta host |
|---|---|---|
| `source-postgres` | ERP simulado (6 tabelas) | 5432 |
| `dw-postgres` | Data Warehouse (raw/staging/marts) | 5433 |
| `airflow-db` | metadados do Airflow | 5434 |
| `airflow-webserver` / `airflow-scheduler` | orquestração | 8080 |
| `meltano` | EL (executado pela DAG; imagem com plugins instalados) | - |
| `dbt` | transformação | 8081 (docs) |
| `metabase` | BI | 3000 |

**Ações.**
- Resolver os conflitos de porta descritos no gap (item 4.2).
- Centralizar variáveis em `.env` / `.env.example` (ver F1-06).
- `depends_on` + healthchecks (source e DW healthy antes do Airflow/Meltano).
- Construir imagem Airflow com Meltano e o provider Postgres (`docker/airflow.Dockerfile`).

**Arquivos afetados.** `docker-compose.yml`, `docker/airflow.Dockerfile`, `.env.example`.

**Critério de aceite.** `docker compose up -d` sobe todos os serviços saudáveis; portas
sem colisão; Airflow acessível em `:8080`.

**Dependências.** F1-02.

---

## F1-04 - Implementar o projeto Meltano (Taps + Targets)

**Descrição.** Centro do rubric de ingestão. Configurar Extractors (Taps) e Loaders
(Targets) no padrão Singer.

**Ações.**
- `meltano init` em `meltano/`; versionar `meltano.yml`.
- **Extractors:**
  - `tap-postgres` -> lê as 6 tabelas relacionais do `source-postgres` (schema `public`).
  - `tap-csv` -> lê `transacoes.csv` (definir schema/encoding/delimitador).
- **Loader:**
  - `target-postgres` -> grava no `dw-postgres`, schema `raw` (bronze).
- Configurar **seleção de streams** (as 7 entidades), **replication-method**
  (`FULL_TABLE` para a POC) e **mapeamento de schema/nomes** consistente com o que o dbt
  espera (`_sources.yml` já lista as 7 tabelas em `raw`).
- Toda credencial via **variável de ambiente** (`$TAP_POSTGRES_PASSWORD`,
  `$TARGET_POSTGRES_PASSWORD`) - nada hardcoded no `meltano.yml`.
- Comandos de referência: `meltano run tap-postgres target-postgres` e
  `meltano run tap-csv target-postgres`.

**Arquivos afetados.** `meltano/meltano.yml`, `meltano/.gitignore`, configs de plugin,
`docker/airflow.Dockerfile` (instalar plugins no build).

**Critério de aceite.** `meltano run tap-postgres target-postgres` e
`meltano run tap-csv target-postgres` populam `raw.*` no DW com as 7 tabelas; contagem de
linhas bate com a fonte; nenhum segredo no `meltano.yml`.

**Dependências.** F1-02, F1-03.

---

## F1-05 - Reescrever a DAG do Airflow (orquestração real)

**Descrição.** Substituir o template Python por uma DAG que orquestra **EL (Meltano)** +
**T (dbt)**, com sensores, retries, idempotência e dependências bem definidas.

**Estrutura de tasks (proposta).**
```
wait_source_ready (FileSensor / SQL sensor)
        │
        ├── el_extract_load_sql   (Meltano: tap-postgres → target-postgres)
        ├── el_extract_load_csv   (Meltano: tap-csv → target-postgres)
        │        (as duas em paralelo)
        ▼
dbt_run        (staging -> marts)
        ▼
dbt_test       (data quality)
        ▼
validate_load  (checagem de contagem fonte × destino)
```

**Ações.**
- `default_args` com `retries=2`, `retry_delay`, `retry_exponential_backoff=True`,
  `execution_timeout`, `on_failure_callback`.
- **Sensor**: `FileSensor` para `transacoes.csv` (disponibilidade do arquivo) e/ou
  `SqlSensor`/check de conectividade na fonte - atende o item "Sensores" do rubric.
- **Idempotência**: re-execução do mesmo `logical_date` produz o mesmo estado (Meltano
  `FULL_TABLE` + `target-postgres` recriando/truncando a tabela raw; sem duplicação).
- Rodar Meltano via `BashOperator` (compose) e `KubernetesPodOperator` (Kind) - abstrair
  para alternar por ambiente.
- Conexões e segredos via **Airflow Connections/Variables** alimentadas por env (F1-06),
  nunca no código da DAG.
- Metadados da DAG: `doc_md`, `tags=["banvic","elt"]`, `catchup=False`, `schedule`.

**Arquivos afetados.** `dags/banvic_elt.py`, `dags/callbacks.py` (callback de falha).

**Critério de aceite.** DAG aparece sem erros de import; executa verde de ponta a ponta;
sensor bloqueia quando o arquivo não existe; ao matar o load e reexecutar, completa via
retry; reexecução não duplica dados (validado em F2-03).

**Dependências.** F1-04.

---

## F1-06 - Segurança e gerenciamento de segredos

**Descrição.** Eliminar credenciais do código e padronizar a injeção de segredos. Critério
de avaliação explícito.

**Ações.**
- Remover **todas** as senhas hardcoded dos compose do template e definir tudo via `.env`.
- `.env.example` completo e documentado, cobrindo a nova topologia:
  ```
  # Source (ERP)
  SOURCE_POSTGRES_USER / _PASSWORD / _DB
  # DW
  DW_POSTGRES_USER / _PASSWORD / _DB
  # Airflow meta
  AIRFLOW_DB_USER / _PASSWORD
  AIRFLOW_FERNET_KEY / AIRFLOW__WEBSERVER__SECRET_KEY
  # Meltano taps/targets (derivam das acima)
  # Metabase
  ```
- **Airflow Connections** (`source_postgres`, `dw_postgres`) injetadas via
  `AIRFLOW_CONN_*` a partir do `.env` - não criar via UI nem no código.
- **Kubernetes Secrets** para as mesmas credenciais (F1-07); manifests referenciam
  `secretKeyRef`, nunca valores literais.
- `git-secrets`/checagem simples no CI (F2-08) para impedir regressão.

**Arquivos afetados.** `.env.example`, `docker-compose.yml`, `k8s/secrets.example.yaml`,
remoção de literais em `Dados - Banvic/banvic/docker/*`.

**Critério de aceite.** `grep` por senhas conhecidas no repositório retorna vazio; subir o
ambiente com `.env` ausente falha de forma clara (sem default inseguro); Secrets aplicados
no Kind.

**Dependências.** F1-03.

---

## F1-07 - Kubernetes local (Kind) - IaC

**Descrição.** Entregar o ambiente em Kubernetes via Kind, atendendo o critério de Infra/IaC.

**Ações.**
- `k8s/kind-cluster.yaml` (config do cluster, port mappings para Airflow/Metabase).
- Implantar:
  - **Postgres source** e **Postgres DW** (StatefulSet ou Deployment + PVC + Service).
  - **Airflow** via **Helm chart oficial** (`apache-airflow/airflow`) com
    `KubernetesExecutor`, `values.yaml` apontando para a imagem custom (Airflow+Meltano),
    `dags`/`gitSync` ou imagem com DAGs embutidas.
  - **Metabase** (Deployment + Service).
- **Secrets** (F1-06) como objetos `Secret`; ConfigMaps para parâmetros não sensíveis.
- Imagens locais carregadas no Kind (`kind load docker-image`).
- `Makefile` com alvos: `kind-up`, `kind-load`, `kind-deploy`, `kind-down`.

**Arquivos afetados.** `k8s/*.yaml`, `k8s/helm/airflow-values.yaml`, `Makefile`,
`docker/airflow.Dockerfile`.

**Critério de aceite.** `make kind-up && make kind-deploy` sobe o cluster; `kubectl get pods`
todos `Running`; Airflow UI acessível via port-forward/mapping; a DAG roda no cluster com
`KubernetesPodOperator`/executor e popula o DW.

**Dependências.** F1-04, F1-05, F1-06.

---

## F1-08 - Reescrever o README (documentação técnica mínima)

**Descrição.** O README precisa refletir a arquitetura real (não só dbt/Metabase). É
entregável avaliado.

**Ações (conteúdo mínimo).**
- **Diagrama de arquitetura** (reaproveitar o de `docs/README.md`).
- **Estratégia de ingestão**: por que Meltano, quais taps/targets, FULL_TABLE,
  idempotência.
- **Passo a passo - docker-compose** (dev) e **- Kubernetes/Kind** (entrega).
- Como acionar a DAG e verificar os dados no destino.
- Seção de segredos (como configurar `.env`/Secrets).
- (O conteúdo rico - narrativa de negócio, dashboards - entra na Fase 3.)

**Arquivos afetados.** `README.md`.

**Critério de aceite.** Uma pessoa sem contexto sobe o ambiente seguindo só o README, em
ambos os modos (compose e Kind), e chega aos dados no DW.

**Dependências.** F1-05, F1-07.

---

## Resumo da Fase 1

| ID | Task | Sev. | Depende de |
|---|---|---|---|
| F1-01 | Higiene + estrutura canônica | IMPORT | - |
| F1-02 | Seed dos dados-fonte (7 tabelas) | CRITICO | F1-01 |
| F1-03 | docker-compose unificado | IMPORT | F1-02 |
| F1-04 | Projeto Meltano (taps/targets) | CRITICO | F1-02, F1-03 |
| F1-05 | DAG Airflow (sensor/retry/idempotência) | CRITICO | F1-04 |
| F1-06 | Segurança / segredos | CRITICO | F1-03 |
| F1-07 | Kubernetes (Kind) - IaC | CRITICO | F1-04, F1-05, F1-06 |
| F1-08 | Reescrita do README | CRITICO | F1-05, F1-07 |

Próximo passo: [`02_fase2_revisao_e_testes.md`](02_fase2_revisao_e_testes.md).
