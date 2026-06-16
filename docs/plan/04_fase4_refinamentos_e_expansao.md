# Fase 4 - Refinamentos e Expansão Analítica

> **Meta da fase:** enriquecer o projeto com análises de alto valor que ampliam a
> narrativa de negócio do BanVic além do pipeline obrigatório — sem alterar a
> infraestrutura ou a camada de staging já estabilizada. Cada item aqui é
> **incremental e independente**: pode ser implementado em qualquer ordem e não
> introduz risco de regressão nas fases anteriores.

**Critério de saída da fase:** novos marts e queries integrados ao dbt, testados e
referenciados no `dicionario_dados.md` e no `roteiro_video.md`; DDL documentado e
inconsistências anotadas.

---

## Considerações sobre o DDL oficial

> O DDL fornecido em dbdiagram.io representa o modelo lógico **simplificado** do
> BanVic. A comparação com os CSVs reais revelou três divergências e dois pontos de
> atenção que impactam a modelagem analítica.

### Divergências DDL × dados reais

| Tabela | Campo no DDL | Campo(s) real(is) no CSV | Impacto | Ação |
|---|---|---|---|---|
| `contas` | `saldo float` | `saldo_total`, `saldo_disponivel` | O DDL omite a separação entre saldo contábil e saldo disponível para saque | Nenhuma — `stg_contas.sql` já mapeia ambos corretamente |
| `colaboradores` | `endenreco varchar` (typo) | `endereco` | Typo sem consequência nos dados reais | Documentar; nenhuma alteração de código |
| `propostas_credito` | sem `cod_agencia` | sem `cod_agencia` | A agência de origem de uma proposta **não é direta** — exige join `colaborador → colaborador_agencia → agencia` | `fct_performance_agencia.sql` já resolve o join; documentar a limitação no dicionário |

### Pontos de atenção para análises futuras

1. **`clientes` não tem `cidade`/`uf`**: apenas `endereco` (string livre) e `cep`.
   Perguntas como *"quantos clientes foram criados em Porto Alegre?"* exigem parse
   do campo `endereco` (ex.: `SPLIT_PART(endereco, ',', -1)`) ou cruzamento com
   uma tabela de CEPs. A base de enriquecimento de clientes (F4-02) é o caminho
   natural para suprir essa limitação.

2. **`propostas_credito` sem `cod_agencia` direto**: a rastreabilidade proposta →
   agência passa obrigatoriamente pela cadeia `cod_colaborador → colaborador_agencia
   → cod_agencia`. Qualquer mart de crédito por agência deve materializar esse join
   (já feito em `fct_performance_agencia`).

3. **DDL não reflete `saldo_disponivel`**: análises de liquidez do cliente devem
   usar `available_balance` de `stg_contas`, não `total_balance`. A distinção já
   existe no staging mas não está explicitada em nenhum mart atual.

---

## F4-01 - Análise de Fraude (transações temporalmente suspeitas)

**Descrição.** O documento de dados menciona (item 20) que algumas transações ficaram
muito próximas entre si (minutos ou segundos) por questão de aleatoriedade do gerador.
Esse padrão é exatamente o que sistemas antifraude buscam: múltiplas transações da
mesma conta em janelas de tempo curtíssimas. Implementar um mart que identifica e
classifica essas ocorrências via **window functions**.

**Valor analítico.** Alta visibilidade técnica: demonstra domínio de `LAG`, `LEAD`,
`PARTITION BY`, e classificação por regras de negócio — tudo em SQL puro dentro do
dbt. Fraude bancária é narrativa de alto impacto para apresentação.

**Ações.**

- Criar `dbt_project/models/marts/mart_analise_fraude.sql`:
  - Usar `LAG(transaction_at) OVER (PARTITION BY account_id ORDER BY transaction_at)`
    para calcular o intervalo entre transações consecutivas da mesma conta.
  - Classificar cada transação com um `fraud_flag`:
    - `suspeita_alta`: intervalo < 60 segundos com a transação anterior.
    - `suspeita_media`: intervalo entre 60 e 300 segundos.
    - `normal`: intervalo > 300 segundos ou primeira transação da conta.
  - Incluir colunas: `transaction_id`, `account_id`, `transaction_at`,
    `prev_transaction_at`, `seconds_since_prev`, `fraud_flag`, `transaction_type`,
    `transaction_amount`.
  - Materializar como `table` (não view) para performance em consultas de BI.

- Criar `dbt_project/models/marts/mart_resumo_fraude.sql`:
  - Agregado por conta: total de alertas por nível, valor total envolvido, data do
    último alerta.
  - Permite responder: *"quais contas têm mais ocorrências suspeitas?"*

- Adicionar testes dbt no `_marts.yml`:
  - `not_null` em `fraud_flag` e `transaction_id`.
  - `accepted_values` em `fraud_flag` (`suspeita_alta`, `suspeita_media`, `normal`).
  - `dbt_utils.expression_is_true`: `seconds_since_prev >= 0` (não pode ser negativo).

- Adicionar query de exemplo em `queries/dashboard_insights.sql` (seção fraude):
  *"Top 10 contas com mais alertas de suspeita alta"*.

**Arquivos afetados.**
```
dbt_project/models/marts/mart_analise_fraude.sql   (novo)
dbt_project/models/marts/mart_resumo_fraude.sql    (novo)
dbt_project/models/marts/_marts.yml               (testes)
queries/dashboard_insights.sql                     (seção adicional)
docs/reference/dicionario_dados.md                           (novos marts)
```

**Critério de aceite.** `dbt build --select mart_analise_fraude mart_resumo_fraude`
verde; testes passam; query retorna contas com alertas; `seconds_since_prev` correto
em transações sabidamente próximas no tempo.

**Dependências.** `stg_transacoes` (já existe). Independente das demais tasks desta fase.

---

## F4-02 - Base Externa de Enriquecimento de Clientes (narrativa de churn)

**Descrição.** O documento de dados sugere (item 11) criar uma base externa com
atributos demográficos dos clientes — `profissao`, `renda_mensal`, `escolaridade` —
com valores **deliberadamente distintos entre clientes churn e não-churn**, para criar
uma narrativa de análise de perfil de abandono. Demonstra ingestão multi-fonte e
cruzamento entre dado operacional (transacional) e dado externo (cadastral enriquecido).

**Valor analítico.** Demonstra dois pontos importantes:
1. **Ingestão de nova fonte** — um segundo CSV externo integrado via `tap-csv` do
   Meltano, mostrando que o pipeline é extensível.
2. **Análise de churn com contexto demográfico** — narrativa de negócio mais rica que
   apenas "cliente inativo há 360 dias".

**Ações.**

- Gerar o arquivo `data/source/clientes_enriquecido.csv` via script Python
  (`scripts/gerar_enriquecimento_clientes.py`):
  - Campos: `cod_cliente` (FK para clientes), `profissao`, `renda_mensal`,
    `escolaridade`, `estado_civil`, `tem_dependentes`.
  - Usar `mart_engajamento_cliente` para identificar clientes com
    `engagement_status = 'churned'` e atribuir perfil deliberadamente distinto:
    - Churned: renda menor, profissões voláteis (autônomo, informal), maior proporção
      solteiros sem dependentes.
    - Ativos: renda maior, profissões estáveis (CLT, servidor público), mais variado.
  - Salvar como CSV; **não versionar no Git** (adicionar ao `.gitignore`).

- Configurar novo stream no Meltano (`meltano/meltano.yml`) para `tap-csv` ler
  `clientes_enriquecido.csv` e carregar em `raw.clientes_enriquecido`.

- Criar `dbt_project/models/staging/stg_clientes_enriquecido.sql`:
  - Renomear colunas para inglês seguindo o padrão do projeto.
  - Cast explícito de `renda_mensal` para `numeric`.

- Criar `dbt_project/models/marts/mart_perfil_churn.sql`:
  - Join `mart_engajamento_cliente` × `stg_clientes_enriquecido`.
  - Calcular médias de renda, distribuição de profissão e escolaridade por
    `engagement_status`.
  - Responde: *"qual o perfil demográfico do cliente que churnou?"*

- Adicionar testes dbt:
  - FK de `stg_clientes_enriquecido.client_id` → `stg_clientes.client_id`
    (severity: `warn` para tolerar clientes sem enriquecimento).
  - `not_null` em `renda_mensal` e `profissao`.

- Atualizar `docs/reference/dicionario_dados.md` com a nova tabela `raw.clientes_enriquecido`.

**Arquivos afetados.**
```
scripts/gerar_enriquecimento_clientes.py           (novo)
data/source/clientes_enriquecido.csv               (gerado, não versionado)
meltano/meltano.yml                                (novo stream tap-csv)
dbt_project/models/staging/stg_clientes_enriquecido.sql (novo)
dbt_project/models/marts/mart_perfil_churn.sql     (novo)
dbt_project/models/staging/_staging.yml            (testes FK)
dbt_project/models/marts/_marts.yml                (testes)
docs/reference/dicionario_dados.md                           (atualização)
.gitignore                                         (clientes_enriquecido.csv)
```

**Critério de aceite.** `meltano run tap-csv target-postgres` carrega
`raw.clientes_enriquecido`; `dbt build --select stg_clientes_enriquecido
mart_perfil_churn` verde; mart mostra diferença mensurável de renda/profissão entre
churned e ativos.

**Dependências.** F4-01 independente. Depende de `mart_engajamento_cliente` (já existe)
para informar o script de geração. Requer atualização do Meltano (pode exigir teste
de integração adicional em `tests/ingestion/test_row_counts.py`).

---

## F4-03 - Tabela de Tarifas e Mart de Faturamento

**Descrição.** O documento de dados sugere (item 14) criar uma tabela de tarifas por
tipo de transação para calcular o faturamento e margem do banco por cliente e agência.
Responde diretamente às perguntas: *"qual cliente deu mais lucro? qual agência?"*

**Valor analítico.** Adiciona dimensão financeira ausente nos marts atuais. A tabela de
tarifas funciona como uma **dimensão de referência** (lookup table) — padrão clássico
de modelagem dimensional. Junto com `fct_volume_diario_transacoes`, permite calcular
receita operacional do banco.

**Ações.**

- Criar `data/source/tarifas_transacao.csv` com as tarifas por tipo (valores fictícios
  mas plausíveis para banco brasileiro):

  | nome_transacao | tarifa_fixa | percentual_sobre_valor | descricao |
  |---|---|---|---|
  | PIX | 0.00 | 0.000 | Isento por regulação Bacen |
  | TED | 12.00 | 0.000 | Tarifa fixa DOC/TED |
  | DOC | 8.00 | 0.000 | Tarifa fixa DOC |
  | Transferência | 5.00 | 0.000 | Transferência interna |
  | Depósito | 0.00 | 0.000 | Depósito isento |
  | Saque | 2.50 | 0.000 | Saque em caixa |

- Criar `dbt_project/models/staging/stg_tarifas_transacao.sql` (seed dbt ou staging
  de CSV — preferir seed dbt com `dbt_project/seeds/tarifas_transacao.csv` para
  evitar dependência do Meltano para uma tabela estática de referência).

- Criar `dbt_project/models/marts/mart_faturamento_cliente.sql`:
  - Join `stg_transacoes` × `stg_contas` × `stg_tarifas_transacao`.
  - Calcular `receita_tarifa = tarifa_fixa + (percentual_sobre_valor * valor_transacao)`.
  - Agregar por cliente: total de transações, receita total, ticket médio, tipo mais usado.
  - Responde: *"qual cliente gerou mais receita de tarifas?"*

- Criar `dbt_project/models/marts/mart_faturamento_agencia.sql`:
  - Join acima + `stg_contas.agency_id`.
  - Agregar por agência: receita total, clientes únicos, transações totais, receita per capita.
  - Responde: *"qual agência é mais rentável?"*

- Adicionar testes dbt:
  - `dbt_utils.expression_is_true`: `receita_tarifa >= 0`.
  - `not_null` em campos de chave e `receita_tarifa`.

- Adicionar queries em `queries/dashboard_insights.sql`:
  - *"Top 10 clientes por receita de tarifas gerada"*
  - *"Receita por agência com evolução anual"*
  - *"Impacto do lançamento do PIX na receita de tarifas (antes/depois nov 2020)"*
    (narrativa: PIX zerou tarifa de muitas transações — queda de receita mensurável).

**Arquivos afetados.**
```
dbt_project/seeds/tarifas_transacao.csv            (novo — seed dbt)
dbt_project/dbt_project.yml                        (registrar seed)
dbt_project/models/marts/mart_faturamento_cliente.sql (novo)
dbt_project/models/marts/mart_faturamento_agencia.sql (novo)
dbt_project/models/marts/_marts.yml                (testes)
queries/dashboard_insights.sql                     (seção faturamento)
docs/reference/dicionario_dados.md                           (novos marts + seed)
```

**Critério de aceite.** `dbt seed && dbt build --select mart_faturamento_cliente
mart_faturamento_agencia` verde; receita de PIX = R$0 para todas as transações PIX;
receita total coerente com volume de transações; query "impacto do PIX" mostra queda
visível em novembro de 2020.

**Dependências.** Independente das demais tasks desta fase. Apenas `stg_transacoes` e
`stg_contas` (já existem).

---

## F4-04 - Análise Estatística Descritiva (opcional)

**Descrição.** O documento de dados sugere (seção "Análise Estatística") calcular
média, variância e modelagem do `valor_transacao`. É o item de menor prioridade da
fase — o SQL cobre média e variância naturalmente, mas Poisson fica forçado fora de
Python/notebook. Implementar o que faz sentido em SQL e registrar a limitação.

**Valor analítico.** Moderado — demonstra consciência estatística, mas não agrega
narrativa de negócio tão forte quanto os itens anteriores. Vale principalmente se
houver dashboard no Metabase que plotar a distribuição.

**Ações.**

- Criar `dbt_project/models/marts/mart_estatisticas_transacoes.sql`:
  - Calcular por `transaction_type` e globalmente: `count`, `avg`, `stddev`, `variance`,
    `percentile_cont(0.5)` (mediana), `percentile_cont(0.95)` (P95), `min`, `max`.
  - Incluir flag `distribuicao_assimetrica`: `stddev > 2 * avg` (indicador prático de
    lognormal — muitas transações pequenas, poucas grandes, confirmando a narrativa do doc).

- **Não implementar** modelagem Poisson em SQL — anotar no modelo que *"a estimativa
  do parâmetro λ e o cálculo de probabilidade P(X=k) requerem Python/notebook e
  estão fora do escopo dbt"*. Isso demonstra discernimento técnico, não lacuna.

- Adicionar query em `queries/dashboard_insights.sql`:
  - Tabela de percentis por tipo de transação (útil no Metabase como tabela de referência).

**Arquivos afetados.**
```
dbt_project/models/marts/mart_estatisticas_transacoes.sql (novo)
dbt_project/models/marts/_marts.yml                       (testes)
queries/dashboard_insights.sql                            (seção estatística)
```

**Critério de aceite.** `dbt build --select mart_estatisticas_transacoes` verde;
`stddev > avg` confirmado nos dados (distribuição lognormal); `avg` de PIX < `avg` de
TED (coerente com a realidade).

**Dependências.** Independente. Apenas `stg_transacoes`.

---

## Resumo da Fase 4

| ID | Task | Valor técnico | Valor narrativo | Esforço | Prioridade |
|---|---|---|---|---|---|
| F4-01 | Análise de fraude (window functions) | Alto | Alto (banco + fraude) | Baixo | **1°** |
| F4-02 | Enriquecimento de clientes (churn) | Médio (nova fonte) | Alto (perfil de churn) | Médio | **2°** |
| F4-03 | Tarifas + faturamento por agência/cliente | Médio (modelagem dimensional) | Alto (receita do banco) | Médio | **3°** |
| F4-04 | Estatísticas descritivas | Baixo-Médio | Baixo | Baixo | **4° (opcional)** |

**Dependências entre tasks:** todas são independentes entre si. A ordem de prioridade
reflete relação esforço/impacto, não pré-requisitos técnicos.

**Integração com fases anteriores:**
- Todos os novos marts entram no mesmo `dbt_project/` e passam pelo mesmo `dbt build`
  da DAG `banvic_elt` — nenhuma alteração na DAG necessária.
- F4-02 é a única que adiciona fonte ao Meltano — requer teste de ingestão adicional
  em `tests/ingestion/test_row_counts.py`.
- Os novos marts devem ser referenciados no `docs/delivery/roteiro_video.md` como demonstração
  da riqueza analítica do projeto.
