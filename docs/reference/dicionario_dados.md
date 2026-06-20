# Dicionário de Dados - BanVic (Banco Vitória S.A.)

> Catálogo de todas as entidades, schemas e modelos do pipeline ELT.
> Organizado por camada (Bronze -> Silver -> Gold -> Metadata).

---

## Visão Geral das Camadas

| Camada | Schema | Responsável | Registros totais | Materialização |
|--------|--------|-------------|-----------------|----------------|
| Bronze | `raw` | Meltano | ~5.200 linhas | Tabelas (FULL_TABLE) |
| Silver | `staging` | dbt | ~5.200 linhas | Views |
| Gold | `marts` | dbt | Agregado | Tables |
| Metadados | `metadata` | dbt macro | Histórico | Tables |

---

## Bronze - Schema `raw`

Dados brutos extraídos do ERP simulado (Source Postgres) e do arquivo CSV de transações.
**Estrutura idêntica à fonte** - nenhuma transformação aplicada.

### `raw.agencias`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `cod_agencia` | INTEGER | Identificador único da agência |
| `nome` | TEXT | Nome da agência |
| `endereco` | TEXT | Endereço completo |
| `cidade` | TEXT | Cidade |
| `uf` | TEXT | Unidade federativa (estado) |
| `data_abertura` | DATE | Data de abertura da agência |
| `tipo_agencia` | TEXT | Categoria da agência |

**Volume**: 10 registros

---

### `raw.clientes`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `cod_cliente` | INTEGER | Identificador único do cliente |
| `primeiro_nome` | TEXT | Primeiro nome |
| `ultimo_nome` | TEXT | Sobrenome |
| `email` | TEXT | E-mail de contato |
| `tipo_cliente` | TEXT | Pessoa Física ou Jurídica |
| `data_inclusao` | TIMESTAMPTZ | Data de cadastro no sistema |
| `cpfcnpj` | TEXT | CPF (PF) ou CNPJ (PJ) |
| `data_nascimento` | DATE | Data de nascimento |
| `endereco` | TEXT | Endereço completo |
| `cep` | TEXT | CEP |

**Volume**: 998 registros  
**Nota**: `cod_cliente=528` está referenciado em `contas` e `propostas_credito` mas **não existe** nesta tabela - inconsistência de integridade referencial da fonte, capturada pelo teste `relationships` do dbt com `severity: warn`.

---

### `raw.colaboradores`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `cod_colaborador` | INTEGER | Identificador único do colaborador |
| `primeiro_nome` | TEXT | Primeiro nome |
| `ultimo_nome` | TEXT | Sobrenome |
| `email` | TEXT | E-mail corporativo |
| `cpf` | TEXT | CPF do colaborador |
| `data_nascimento` | DATE | Data de nascimento |
| `endereco` | TEXT | Endereço completo |
| `cep` | TEXT | CEP |

**Volume**: 100 registros

---

### `raw.colaborador_agencia`

Tabela de junção N:N entre colaboradores e agências.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `cod_colaborador` | INTEGER | FK -> colaboradores.cod_colaborador |
| `cod_agencia` | INTEGER | FK -> agencias.cod_agencia |

**Volume**: 100 registros  
**PK composta**: `(cod_colaborador, cod_agencia)`

---

### `raw.contas`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `num_conta` | INTEGER | Identificador único da conta |
| `cod_cliente` | INTEGER | FK -> clientes.cod_cliente |
| `cod_agencia` | INTEGER | FK -> agencias.cod_agencia |
| `cod_colaborador` | INTEGER | FK -> colaboradores (colaborador responsável) |
| `tipo_conta` | TEXT | Tipo da conta bancária |
| `data_abertura` | TIMESTAMPTZ | Data de abertura da conta |
| `saldo_total` | NUMERIC | Saldo total consolidado |
| `saldo_disponivel` | NUMERIC | Saldo disponível para movimentação |
| `data_ultimo_lancamento` | TIMESTAMPTZ | Data do último lançamento |

**Volume**: 999 registros

---

### `raw.propostas_credito`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `cod_proposta` | INTEGER | Identificador único da proposta |
| `cod_cliente` | INTEGER | FK -> clientes.cod_cliente |
| `cod_colaborador` | INTEGER | FK -> colaboradores (analista responsável) |
| `data_entrada_proposta` | TIMESTAMPTZ | Data de entrada da proposta |
| `taxa_juros_mensal` | NUMERIC | Taxa de juros mensal proposta |
| `valor_proposta` | NUMERIC | Valor total solicitado |
| `valor_financiamento` | NUMERIC | Valor a ser financiado |
| `valor_entrada` | NUMERIC | Valor de entrada |
| `valor_prestacao` | NUMERIC | Valor da prestação mensal |
| `quantidade_parcelas` | INTEGER | Número de parcelas |
| `carencia` | INTEGER | Meses de carência |
| `status_proposta` | TEXT | Estágio no funil: `Aprovada`, `Em análise`, `Enviada`, `Validação documentos` |

**Volume**: 2.000 registros

---

### `raw.transacoes`

Origem: arquivo `transacoes.csv` depositado na landing zone. Ingerido via `tap-csv`.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `cod_transacao` | TEXT (-> BIGINT no staging) | Identificador único da transação |
| `num_conta` | TEXT (-> BIGINT no staging) | FK -> contas.num_conta |
| `data_transacao` | TEXT (-> TIMESTAMPTZ no staging) | Data e hora da transação |
| `nome_transacao` | TEXT | Tipo/nome da transação |
| `valor_transacao` | TEXT (-> NUMERIC no staging) | Valor da transação |

**Nota**: `tap-csv` carrega todas as colunas como TEXT. O casting para tipos corretos ocorre na camada Silver (`stg_transacoes`).

---

## Silver - Schema `staging`

Views dbt que limpam, renomeiam e tipam os dados Bronze.  
**Convenção**: colunas renomeadas para inglês; IDs sufixados com `_id`.

### `staging.stg_agencias`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `agency_id` | INTEGER | Identificador único (<- cod_agencia) |
| `agency_name` | TEXT | Nome da agência |
| `address` | TEXT | Endereço |
| `city` | TEXT | Cidade |
| `state` | TEXT | Estado (UF) |
| `opening_date` | DATE | Data de abertura |
| `agency_type` | TEXT | Tipo de agência |

**Testes**: `agency_id` unique + not_null

---

### `staging.stg_clientes`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `client_id` | INTEGER | Identificador único (<- cod_cliente) |
| `client_full_name` | TEXT | Nome completo concatenado |
| `email` | TEXT | E-mail |
| `client_type` | TEXT | Tipo de cliente |
| `onboarding_date` | TIMESTAMPTZ | Data de cadastro |
| `cpf_cnpj` | TEXT | Documento |
| `birth_date` | DATE | Data de nascimento |
| `address` | TEXT | Endereço |
| `postal_code` | TEXT | CEP |

**Testes**: `client_id` unique + not_null

---

### `staging.stg_colaboradores`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `employee_id` | INTEGER | Identificador único (<- cod_colaborador) |
| `first_name` | TEXT | Primeiro nome |
| `last_name` | TEXT | Sobrenome |
| `email` | TEXT | E-mail corporativo |
| `cpf` | TEXT | CPF |
| `birth_date` | DATE | Data de nascimento |
| `address` | TEXT | Endereço |
| `postal_code` | TEXT | CEP |

**Testes**: `employee_id` unique + not_null

---

### `staging.stg_colaborador_agencia`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `employee_id` | INTEGER | FK -> stg_colaboradores.employee_id |
| `agency_id` | INTEGER | FK -> stg_agencias.agency_id |

**Testes**: `employee_id` not_null, `agency_id` not_null

---

### `staging.stg_contas`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `account_id` | INTEGER | Identificador único (<- num_conta) |
| `client_id` | INTEGER | FK -> stg_clientes (severity: warn) |
| `agency_id` | INTEGER | FK -> stg_agencias |
| `employee_id` | INTEGER | FK -> stg_colaboradores |
| `account_type` | TEXT | Tipo de conta |
| `opening_date` | TIMESTAMPTZ | Data de abertura |
| `total_balance` | NUMERIC | Saldo total |
| `available_balance` | NUMERIC | Saldo disponível |
| `last_posting_date` | TIMESTAMPTZ | Último lançamento |

**Testes**: `account_id` unique + not_null; `client_id` relationships (warn - defeito conhecido)

---

### `staging.stg_propostas_credito`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `proposal_id` | INTEGER | Identificador único (<- cod_proposta) |
| `client_id` | INTEGER | FK -> stg_clientes (severity: warn) |
| `employee_id` | INTEGER | FK -> stg_colaboradores |
| `proposal_date` | TIMESTAMPTZ | Data de entrada |
| `monthly_interest_rate` | NUMERIC | Taxa de juros mensal |
| `proposal_amount` | NUMERIC | Valor solicitado |
| `financing_amount` | NUMERIC | Valor a financiar |
| `down_payment` | NUMERIC | Valor de entrada |
| `installment_amount` | NUMERIC | Valor da prestação |
| `installment_count` | INTEGER | Número de parcelas |
| `grace_period` | INTEGER | Meses de carência |
| `proposal_status` | TEXT | Status: `Aprovada` · `Em análise` · `Enviada` · `Validação documentos` |

**Testes**: `proposal_id` unique + not_null; `proposal_status` accepted_values

---

### `staging.stg_transacoes`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `transaction_id` | BIGINT | Identificador único (<- cod_transacao, cast de TEXT) |
| `account_id` | BIGINT | FK -> stg_contas.account_id |
| `transaction_at` | TIMESTAMPTZ | Data e hora (<- data_transacao, cast + timezone) |
| `transaction_type` | TEXT | Tipo/nome da transação |
| `transaction_amount` | NUMERIC | Valor (<- valor_transacao, cast de TEXT) |

**Testes**: `transaction_id` unique + not_null; `account_id` not_null + relationships

---

## Gold - Schema `marts`

Modelos orientados a decisão de negócio. Todos materializados como `table` (DROP + CREATE)
para garantir idempotência e performance no Metabase.

### `marts.fct_atividade_contas`

**Propósito**: classificar contas por nível de atividade para identificar carteiras dormentes.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `account_sk` | INTEGER | SK da conta (PK) |
| `client_fk` | INTEGER | FK -> dimensão cliente |
| `agency_fk` | INTEGER | FK -> dimensão agência |
| `total_balance` | NUMERIC | Saldo total atual |
| `last_transaction_date` | DATE | Data da última transação |
| `days_since_last_transaction` | INTEGER | Dias sem movimentação |
| `activity_status` | TEXT | `active` (≤90d) · `dormant` (>90d) · `never_used` |

**Testes**: `account_sk` unique + not_null; `activity_status` accepted_values  
**Fonte**: `stg_contas` ✕ `stg_transacoes`

---

### `marts.fct_funil_credito`

**Propósito**: acompanhamento mensal do funil de crédito por status de proposta.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `month` | TIMESTAMPTZ | Mês de referência (date_trunc) |
| `proposal_status` | TEXT | Status da proposta |
| `proposal_count` | BIGINT | Quantidade de propostas no período |
| `total_proposal_amount` | NUMERIC | Volume total solicitado |
| `avg_interest_rate` | NUMERIC | Taxa média de juros |

**Testes**: combinação única `(month, proposal_status)`; `month` + `proposal_status` not_null  
**Fonte**: `stg_propostas_credito`

---

### `marts.fct_performance_agencia`

**Propósito**: ranking de agências por volume e taxa de conversão de crédito.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `agency_sk` | INTEGER | SK da agência (PK) |
| `agency_name` | TEXT | Nome da agência |
| `agency_type` | TEXT | Tipo de agência |
| `total_proposals` | BIGINT | Total de propostas vinculadas |
| `approved_proposals` | BIGINT | Propostas aprovadas |
| `conversion_rate_pct` | NUMERIC | Taxa de conversão (%) |
| `total_proposal_amount` | NUMERIC | Volume total |

**Testes**: `agency_sk` unique + not_null  
**Fonte**: `stg_agencias` ✕ `stg_colaborador_agencia` ✕ `stg_propostas_credito`

---

### `marts.fct_volume_diario_transacoes`

**Propósito**: série temporal de volume de transações por dia e tipo, para análise de sazonalidade.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `transaction_date` | DATE | Data da transação |
| `transaction_type` | TEXT | Tipo de transação |
| `transaction_count` | BIGINT | Quantidade de transações |
| `distinct_accounts` | BIGINT | Contas únicas que transacionaram |
| `avg_tx_per_account` | NUMERIC | Média de transações por conta |

**Testes**: combinação única `(transaction_date, transaction_type)`  
**Fonte**: `stg_transacoes`

---

### `marts.mart_kpi_resumo_credito`

**Propósito**: tabela de 1 linha com KPIs executivos de crédito pré-calculados. Zero agregação
necessária no Metabase - resultado direto em qualquer dashboard.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `total_proposals` | BIGINT | Total de propostas histórico |
| `approved_proposals` | BIGINT | Total aprovadas |
| `rejected_proposals` | BIGINT | Total não aprovadas |
| `approval_rate_pct` | NUMERIC | Taxa de aprovação (%) |
| `total_proposal_amount` | NUMERIC | Volume total solicitado (R$) |
| `total_financed_amount` | NUMERIC | Volume total aprovado (R$) |
| `avg_interest_rate_pct` | NUMERIC | Taxa média de juros (%) |

**Testes**: `total_proposals = approved + rejected` (expression_is_true); todos not_null  
**Fonte**: `fct_funil_credito`

---

### `marts.mart_oportunidade_crosssell`

**Propósito**: lista de clientes com alto saldo e sem crédito aprovado - candidatos a oferta ativa.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `client_fk` | INTEGER | FK -> dimensão cliente |
| `client_full_name` | TEXT | Nome completo |
| `account_fk` | INTEGER | FK -> dimensão conta |
| `total_balance` | NUMERIC | Saldo total (> R$ 20.000 por filtro) |
| `agency_fk` | INTEGER | FK -> dimensão agência |

**Filtro aplicado**: `total_balance > 20000 AND cliente sem proposta aprovada`  
**Testes**: `client_fk` + `account_fk` unique + not_null  
**Fonte**: `stg_contas` x `stg_clientes` x `stg_propostas_credito`

---

### `marts.mart_engajamento_cliente`

**Propósito**: engajamento comercial por cliente (narrativa Camila Diniz) - base para transações
por cliente, clientes ativos e risco de churn. Grão: 1 linha por cliente com conta.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `client_sk` | INTEGER | SK do cliente (PK) |
| `client_full_name` | TEXT | Nome completo |
| `client_type` | TEXT | Tipo de cliente (PF/PJ) |
| `onboarding_date` | DATE | Data de inclusão do cliente |
| `account_count` | BIGINT | Número de contas do cliente |
| `total_balance` | NUMERIC | Saldo somado das contas (R$) |
| `transaction_count` | BIGINT | Total de transações do cliente |
| `transaction_total_amount` | NUMERIC | Volume transacionado (R$) |
| `avg_tx_per_account` | NUMERIC | Média de transações por conta |
| `last_transaction_date` | DATE | Data da última transação |
| `days_since_last_transaction` | INTEGER | Recência em dias |
| `relationship_days` | INTEGER | Tempo de relacionamento em dias |
| `has_approved_credit` | BOOLEAN | Possui proposta de crédito aprovada |
| `engagement_status` | TEXT | `active` / `at_risk` / `churned` / `never_used` |

**Regra de status**: active (<= 90d), at_risk (91-360d), churned (> 360d), never_used (sem transação)  
**Testes**: `client_sk` unique + not_null; `engagement_status` accepted_values; `account_count` >= 1; `transaction_count` >= 0  
**Fonte**: `stg_clientes`, `stg_contas`, `stg_transacoes`, `stg_propostas_credito`

---

### `marts.mart_kpi_comercial`

**Propósito**: tabela de 1 linha com KPIs comerciais (narrativa Camila Diniz) pré-calculados
para o dashboard - zero agregação no Metabase.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `total_clientes` | BIGINT | Total de clientes com conta |
| `clientes_ativos` | BIGINT | Status active |
| `clientes_em_risco` | BIGINT | Status at_risk |
| `clientes_churned` | BIGINT | Status churned |
| `clientes_sem_uso` | BIGINT | Status never_used |
| `taxa_ativos_pct` | NUMERIC | % de clientes ativos |
| `taxa_inativos_pct` | NUMERIC | % em risco + churned |
| `media_transacoes_por_cliente` | NUMERIC | Média de transações por cliente |
| `taxa_posse_credito_pct` | NUMERIC | % de clientes com crédito aprovado |

**Testes**: partição completa (`total = ativos + em_risco + churned + sem_uso`); taxas em [0, 100]  
**Fonte**: `mart_engajamento_cliente`

---

### `marts.mart_ranking_alavancas`

**Propósito**: ranking quantitativo de alavancas (narrativa CEO Sofia Oliveira) - correlação de
Pearson entre drivers candidatos e a métrica-alvo (transações por cliente), com significância.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `driver` | TEXT | Alavanca avaliada |
| `correlation` | NUMERIC | Coeficiente de correlação de Pearson [-1, 1] |
| `abs_correlation` | NUMERIC | Valor absoluto (força do efeito) |
| `direction` | TEXT | `positivo` / `negativo` / `indefinido` |
| `sample_size` | BIGINT | Tamanho da amostra (n) |
| `t_statistic` | NUMERIC | Estatística t para teste de significância |
| `significant_at_5pct` | BOOLEAN | Significativo a 5% (\|t\| > 1,96) |
| `impact_rank` | BIGINT | Ranking por força de correlação (1 = maior) |

**Drivers avaliados**: saldo_total, tempo_relacionamento, quantidade_contas, posse_credito_aprovado
**Nota**: `quantidade_contas` é avaliado no SQL mas filtrado do resultado pois todos os 998 clientes possuem exatamente 1 conta (variância zero → `corr()` retorna NULL → `WHERE correlation IS NOT NULL` exclui a linha). O mart retorna 3 dos 4 drivers candidatos.
**Limitação**: correlação indica associação, não causalidade  
**Testes**: `driver` + `impact_rank` unique + not_null; `direction` accepted_values  
**Fonte**: `mart_engajamento_cliente`

---

### `marts.meta_data_quality` *(view)*

**Propósito**: dashboard de qualidade consultável via Metabase ou psql - agrega PASS/FAIL
dos principais testes de integridade diretamente sobre os dados, não apenas definições.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `model_name` | TEXT | Modelo testado |
| `column_name` | TEXT | Coluna testada |
| `test_type` | TEXT | Tipo de teste (not_null, unique, relationships) |
| `status` | TEXT | `PASS` ou `FAIL` |
| `failure_count` | BIGINT | Registros com falha |
| `message` | TEXT | Descrição da falha |

**Nota**: materializada como `view` - reflete sempre o estado atual dos dados.

---

### `marts.meta_models` *(view)*

**Propósito**: catálogo vivo de todos os modelos com tamanho, contagem de linhas e camada medallion.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `model_name` | TEXT | Nome do modelo/tabela |
| `schema_name` | TEXT | Schema no banco |
| `materialization` | TEXT | table / view |
| `row_count` | BIGINT | Estimativa de linhas |
| `total_size` | TEXT | Tamanho total (pg_total_relation_size) |
| `table_size` | TEXT | Tamanho da tabela sem índices |
| `medallion_layer` | TEXT | `bronze` / `silver` / `gold` |
| `captured_at` | TIMESTAMPTZ | Momento da consulta |

---

## Metadata - Schema `metadata`

Tabelas de observabilidade populadas pela macro dbt `populate_test_results()` no `on-run-end`.

### `metadata.test_results`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `test_name` | TEXT | Nome do teste dbt (e.g. `unique_stg_clientes_client_id`) |
| `model_name` | TEXT | Modelo alvo do teste |
| `column_name` | TEXT | Coluna testada (`N/A` para testes de modelo) |
| `status` | TEXT | `pass` / `fail` / `warn` / `error` |
| `message` | TEXT | Mensagem de erro quando `fail` ou `warn` |
| `executed_at` | TIMESTAMPTZ | Timestamp de inserção (DEFAULT NOW()) |

**Populado por**: macro `populate_test_results()` via `on-run-end` do `dbt test`

---

### `metadata.model_runs`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `model_name` | TEXT | Nome do modelo |
| `materialization` | TEXT | Tipo de materialização |
| `schema_name` | TEXT | Schema de destino |
| `row_count` | BIGINT | Linhas após execução |
| `status` | TEXT | Status de execução |
| `message` | TEXT | Mensagem de diagnóstico |
| `executed_at` | TIMESTAMPTZ | Timestamp de inserção |

---

## Inconsistências Conhecidas da Fonte

| # | Entidade | Descrição | Impacto | Tratamento |
|---|----------|-----------|---------|------------|
| 1 | `clientes` × `contas` | `cod_cliente=528` em `contas` sem registro em `clientes` | FK inválida | Teste `relationships` com `severity: warn` em `stg_contas.client_id` |
| 2 | `clientes` × `propostas_credito` | Mesmo `cod_cliente=528` em proposta de R$ 74k | FK inválida | Teste `relationships` com `severity: warn` em `stg_propostas_credito.client_id` |

**Decisão de design**: manter os registros e usar `severity: warn` - o dbt captura o defeito
na camada Silver, gera evidência em `metadata.test_results`, mas não bloqueia o pipeline.
Os marts de Gold excluem indiretamente o cliente 528 em joins que exigem `stg_clientes`.
