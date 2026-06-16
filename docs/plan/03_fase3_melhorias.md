# Fase 3 - Melhorias e Entregáveis Finais

> **Meta da fase:** elevar a nota e completar os **entregáveis obrigatórios que não são
> código de pipeline** (Modelo Conceitual, vídeo, README rico), além de explorar a
> **narrativa de negócio** do case - dashboard comercial (Camila) e o **ranking quantitativo
> de alavancas** que a CEO (Sofia) pede. Também consolida observabilidade e qualidade de
> código.

**Critério de saída da fase:** todos os entregáveis do `Instruções.docx` presentes e
prontos para submissão (`CEA_AW_SEUNOME`).

---

## F3-01 - Modelo Conceitual (entregável obrigatório) OK

**Descrição.** O desafio exige o **Modelo Conceitual** na pasta de entrega.

**Entregue.**
- `docs/architectures/modelo_conceitual.drawio` - ER simplificado, user-friendly, com 6
  entidades, cardinalidades crow's foot e labels de relacionamento de negócio.
- `docs/architectures/arquitetura_dados.drawio` - stack técnica completa: Airflow, Meltano,
  dbt, DW (Medallion), CI/CD, Kind/Compose, testes.
- Ambos referenciados no README com tabela de links.

**Dependências.** -

---

## F3-02 - Dashboard comercial (narrativa Camila Diniz) OK

**Descrição.** A área comercial quer **aumentar transações por cliente**, manter clientes
**ativos** e **reduzir churn**.

**Entregue.**
- `mart_engajamento_cliente`: 1 linha por cliente com transações, recência, saldo, posse de
  crédito e `engagement_status` (active <= 90d / at_risk 91-360d / churned > 360d / never_used).
- `mart_kpi_comercial`: single-row com KPIs de topo (clientes ativos, taxa de inativos,
  média de transações por cliente, taxa de posse de crédito).
- `queries/dashboard_comercial.sql`: queries prontas para os cards do Metabase.
- Testes dbt (accepted_values, accepted_range, partição) + 9 testes de integração pytest.

**Critério de aceite.** Marts respondem às perguntas comerciais do case e alimentam o Metabase.

**Dependências.** Fase 1 (dados no DW).

---

## F3-03 - Ranking quantitativo de alavancas (narrativa CEO Sofia) OK

**Descrição.** A CEO **não quer só "o que tem relação com sucesso"** - quer um **ranking
quantitativo do que é mais impactante**, com retorno "garantido estatisticamente".

**Entregue.**
- `mart_ranking_alavancas`: métrica-alvo = transações por cliente; drivers = saldo, tempo de
  relacionamento, quantidade de contas e posse de crédito.
- Correlação de Pearson (`corr()` do Postgres) por driver, `t_statistic`, flag
  `significant_at_5pct` e `impact_rank` ordenável.
- Limitação documentada no próprio modelo: correlação indica associação, não causalidade
  (inferência causal exigiria regressão multivariada controlada).
- Testes dbt (unique/not_null/accepted_values) + testes de integração (densidade do rank,
  correlação em [-1, 1]).

**Critério de aceite.** Ranking ordenado e reprodutível com medida de impacto e significância,
respondendo diretamente à pergunta da CEO.

**Dependências.** Fase 1, F3-02.

---

## F3-04 - Observabilidade e monitoramento avançado

**Descrição.** Ir além do "monitoramento básico" para reforçar resiliência.

**Ações.**
- `on_failure_callback`/`on_retry_callback` com mensagem útil (log estruturado; opcional
  webhook Slack).
- `sla`/`sla_miss_callback` nas tasks críticas.
- Métricas de execução (duração, linhas carregadas) logadas; opcional exposição via
  `meta_models`/`meta_data_quality` (já existentes) atualizados pós-carga.
- Documentar como inspecionar logs no Airflow (compose e Kind).

**Arquivos afetados.** `dags/callbacks.py`, `dags/banvic_elt.py`, docs.

**Critério de aceite.** Falhas geram alerta observável; SLA configurado; métricas básicas
disponíveis.

**Dependências.** F1-05, F2-05.

---

## F3-05 - Qualidade de código e DX OK (parcial)

**Descrição.** Reforçar o critério "código limpo, modular".

**Entregue.**
- `pyproject.toml` com configuração `ruff` (lint CI) e `pytest`.
- `dags/banvic_elt.py` revisado: docstring correta, sem "what comments", sem kwargs default
  redundantes (`soft_fail=False`), tasks ordenadas na ordem de execução real.
- `dags/callbacks.py` limpo: TYPE_CHECKING guard, lazy logging, sem código morto.
- `Makefile` com alvos `up`, `down`, `dbt-run`, `dbt-test`, `kind-up`, `kind-deploy`, `help`.
- `doc_md` na DAG com tabela de etapas e nota de idempotência.

**Pendente.**
- `pre-commit` local (`.pre-commit-config.yaml`) não configurado - `ruff` cobre o CI.
- `sqlfluff` e `yamllint` não integrados.

**Dependências.** Fase 1.

---

## F3-06 - Documentação final + roteiro do vídeo + pacote de entrega OK (roteiro entregue)

**Descrição.** Fechar os entregáveis formais do `Instruções.docx`.

**Entregue.**
- **README** final: diagrama ASCII, Mermaid sequenceDiagram, passo a passo compose + Kind,
  tabela de serviços/portas, estratégia de ingestão, seção de segurança, comandos úteis.
- **`docs/reference/decisoes_tecnicas.md`** - 11 ADRs (Airflow, Meltano, FULL_TABLE, dbt, materialização,
  gate de validação, topologia da DAG, Medallion, qualidade, infra, testes).
- **`docs/reference/dicionario_dados.md`** - catálogo completo: Bronze/Silver/Gold/Metadata com schemas
  por coluna, volumes e inconsistências conhecidas.

**Pendente.**
- **`docs/delivery/roteiro_video.md`** - roteiro do vídeo 3-5 min (última etapa, explicitamente deferida).
- **Pacote de entrega** `CEA_AW_SEUNOME` - montagem após gravação do vídeo.

**Arquivos afetados.** `docs/delivery/roteiro_video.md`, `docs/checklist_entrega.md`.

**Dependências.** Fases 1 e 2 completas; F3-01.

---

## Resumo da Fase 3

| ID | Task | Tipo | Obrigatório? | Status |
|---|---|---|---|---|
| F3-01 | Modelo Conceitual | Entregável | **Sim** | OK |
| F3-02 | Dashboard comercial (Camila) | Melhoria/Negócio | Não (alto valor) | OK |
| F3-03 | Ranking de alavancas (CEO) | Melhoria/Negócio | Não (alto valor) | OK |
| F3-04 | Observabilidade avançada | Melhoria | Não | - |
| F3-05 | Qualidade de código / DX | Melhoria | Não | OK (parcial) |
| F3-06 | Docs finais + vídeo + pacote | Entregável | **Sim** | PEND vídeo pendente |

---

## Checklist final de aprovação (mapeado ao rubric)

- [x] Ambiente sobe em **Docker** e em **Kubernetes (Kind)**.
- [x] Ingestão com **Meltano** (taps/targets) movendo as 7 tabelas para o DW.
- [x] **DAG Airflow** com tasks, dependências, **sensor**, **retries** e **idempotência**.
- [x] **Monitoramento** e tratamento de falhas demonstráveis (`on_failure_callback`).
- [x] **Nenhuma credencial** em código (segredos via `.env`/k8s Secrets).
- [x] **Testes** de ingestão, idempotência, DAG e resiliência (41 unit verdes no CI; 31 integração locais).
- [x] **README** com diagrama, passo a passo e estratégia de ingestão.
- [x] **Modelo Conceitual** entregue (`docs/architectures/modelo_conceitual.drawio`).
- [ ] **Vídeo 3-5 min** (deploy -> DAG verde -> dados no destino) - roteiro em `docs/delivery/roteiro_video.md`, gravação pendente.
- [x] (Bônus) Dashboard comercial + ranking estatístico da CEO (marts + queries entregues).
