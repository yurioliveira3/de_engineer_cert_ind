# Roteiro do Vídeo - BanVic ELT Pipeline

**Duração total:** 4:45 - 4:50 minutos
**Formato:** screen recording + narração
**Ambiente:** Kubernetes local com Kind (KubernetesExecutor)
**Estrutura:** 7 etapas faseadas, cada uma com o que mostrar na tela e o que falar

> **Estratégia de gravação:** tudo pré-carregado e rodando antes de gravar.
> A única ação ao vivo é o `kubectl get pods` na Etapa 2 — o resto é mostrar
> telas/saídas já prontas e narrar por cima.

---

## Etapa 1 — Apresentação e Arquitetura `[0:00 - 0:30]`

**O que mostrar na tela**
- Abra `docs/architectures/arquitetura_dados.drawio` no draw.io (ou a imagem exportada)
- Aponte com o cursor para as zonas à medida que fala

**O que falar**
> "Olá, apresento o case BanVic — uma pipeline ELT completa desenvolvida como
> entregável da Certificação Data Engineer da Indicium.
>
> O projeto cobre toda a stack: ingestão com Meltano, orquestração com Airflow em
> Kubernetes, transformação com dbt em arquitetura Medallion e visualização no
> Metabase. Tudo roda em Kubernetes local com Kind. Vamos ver isso funcionando."

---

## Etapa 2 — Deploy no Kubernetes `[0:30 - 1:15]`

**O que mostrar na tela**
1. Terminal — rode `kubectl get pods -n banvic` ao vivo (única ação do vídeo)
2. Aponte para os pods conforme fala

**O que falar**
> "O ambiente completo sobe em Kubernetes local com Kind — um único comando `make
> kind-start` cria o cluster, constrói a imagem, gera os Secrets e aplica todos os
> manifests.
>
> Aqui estão os pods: source-postgres com os dados do ERP, o Data Warehouse,
> o Metabase, e o Airflow com scheduler, webserver e triggerer — todos Running.
>
> Nenhuma credencial está no código — as senhas partem do `.env` e são convertidas
> em Kubernetes Secrets. O Airflow recebe suas conexões via `secretKeyRef`, sem
> configuração manual na UI."

```bash
kubectl get pods -n banvic
```

---

## Etapa 3 — Orquestração: DAG no Airflow `[1:15 - 2:15]`

**O que mostrar na tela**
1. Airflow UI (`http://localhost:8080`) — DAG `banvic_elt` com execução já verde
2. Graph View — topologia da DAG
3. Clique em `validate_raw_load` → Logs — as 7 contagens já visíveis

**O que falar**
> "Aqui está a DAG `banvic_elt`. A topologia implementa boas práticas de orquestração:
>
> Começa com um FileSensor que bloqueia até o arquivo de transações estar disponível.
> Em paralelo, o Meltano extrai as 6 tabelas do ERP e o CSV de transações simultaneamente.
>
> Antes de qualquer transformação, o gate `validate_raw_load` confirma que as 7 tabelas
> `raw.*` foram populadas — se alguma estiver vazia, falha aqui com erro claro. Só então
> o dbt roda: transformações e depois testes de qualidade.
>
> Com KubernetesExecutor, cada task executou como um pod isolado no cluster. Todas têm
> retries com backoff exponencial e on_failure_callback que loga erros estruturados."

---

## Etapa 4 — Ingestão e Transformação (Meltano + dbt) `[2:15 - 3:05]`

**O que mostrar na tela**
1. Abra `meltano/meltano.yml` no editor — mostre taps, target e jobs
2. Abra `dbt_project/dbt_project.yml` — mostre materialização por camada
3. (Opcional) Abra um staging model e um mart no editor

**O que falar**
> "Aqui está a configuração da ingestão. O Meltano define dois extractors: `tap-postgres`
> para as 6 tabelas do ERP e `tap-csv` para o arquivo de transações. Ambos carregam no
> `target-postgres` no schema `raw`, com `FULL_TABLE` — cada execução recria as tabelas
> do zero, garantindo idempotência. Os dois jobs `el-sql` e `el-csv` são o que o Airflow
> invoca via BashOperator.
>
> A transformação fica no dbt, com arquitetura Medallion em três camadas: `raw` é a
> bronze do Meltano, `staging` são views na silver e `marts` são tables na gold.
> A materialização é definida por pasta no `dbt_project.yml` — staging como view por
> ser leve e refletir sempre o estado atual do raw, e marts como table para consumo
> direto no Metabase, com DROP e CREATE a cada run."

---

## Etapa 5 — Dados no Destino (DBeaver) `[3:05 - 3:35]`

**O que mostrar na tela**
1. DBeaver conectado ao DW (`localhost:5433`, database `analytics_dw`)
2. Expanda o lado esquerdo: schemas `raw`, `staging`, `marts`, `metadata`
3. Expanda `raw` — mostre as 7 tabelas
4. Abra uma query rápida: `SELECT count(*) FROM raw.transacoes` ou o `pg_stat_user_tables`
5. Expanda `marts` — mostre os 11 modelos

**O que falar**
> "Com a DAG verde, os dados chegaram no destino. Aqui no DBeaver podemos ver a
> estrutura completa do Data Warehouse.
>
> No schema `raw`, a camada bronze, as 7 tabelas populadas pelo Meltano. No schema
> `marts`, a camada gold, os 11 modelos de negócio criados pelo dbt — engajamento,
> KPIs comerciais, ranking de alavancas, funil de crédito, entre outros. Tudo
> organizado na arquitetura Medallion."

---

## Etapa 6 — CI e Testes `[3:35 - 4:25]`

**O que mostrar na tela**
1. Página do GitHub Actions no repositório — mostre os 4 jobs verdes
2. Terminal com a saída já pronta do pytest: `41 passed, 31 deselected`

**O que falar**
> "O repositório tem CI no GitHub Actions com quatro jobs independentes que rodam a
> cada push: lint com ruff, yamllint e sqlfluff; testes unitários do Airflow; dbt
> parse para validar a compilação; e validação da configuração do Meltano. Tudo verde.
>
> O projeto tem 72 testes automatizados no total: 41 unitários e 31 de integração,
> cobrindo topologia da DAG, resiliência a falhas, configuração do Meltano, governança
> dos modelos dbt e integridade dos dados. Os 41 unitários são os que rodam no CI —
> sem banco, rápidos. Os 31 de integração rodam contra o banco real via
> `make test-integration`.
>
> Além dos testes pytest, o dbt executa mais 69 data tests — dois deles geram alerta
> de warn, capturando uma inconsistência real de integridade referencial no dado fonte:
> o cliente 528 existe em contas e propostas de crédito, mas não no cadastro de
> clientes. O pipeline não é interrompido, mas o defeito fica registrado em
> metadata.test_results. Isso demonstra que a camada Silver detecta defeitos antes
> de contaminar a Gold."

---

## Etapa 7 — Metabase e Encerramento `[4:25 - 4:50]`

**O que mostrar na tela**
1. Metabase (`http://localhost:3000`) — dashboard comercial brevemente
2. Feche com o `README.md` aberto

**O que falar**
> "Os marts da camada Gold ficam disponíveis para consumo direto no Metabase — aqui
> está o dashboard comercial, com a distribuição de clientes por status de engajamento
> e o ranking de alavancas para a CEO. Sem camada intermediária, sem planilha — o BI
> consome direto do Data Warehouse.
>
> Isso cobre o pipeline completo: ingestão com Meltano, orquestração com Airflow em
> Kubernetes, transformação com dbt em arquitetura Medallion, qualidade assegurada por
> 72 testes e visualização no Metabase. Para mais detalhes, acesse o README do
> repositório. Obrigado!"

---

## Checklist antes de gravar

**Kubernetes / Kind**
- [ ] Cluster Kind no ar, todos os pods `Running`
- [ ] `make kind-start` executado com sucesso
- [ ] `make kind-upgrade` aplicado (PV de logs — sem isso os logs das tasks não aparecem na UI)
- [ ] DAG `banvic_elt` executada e verde no histórico
- [ ] Logs da task `validate_raw_load` visíveis na UI

**DBeaver**
- [ ] Conectado ao DW (`localhost:5433`, database `analytics_dw`, usuário `analytics`)
- [ ] Schemas `raw`, `staging`, `marts`, `metadata` visíveis no sidebar

**Metabase**
- [ ] Metabase configurado (`http://localhost:3000`) com conexão ao DW
- [ ] Dashboard comercial visível (engajamento + ranking)

**Arquivos para abrir no editor**
- [ ] `meltano/meltano.yml` (Etapa 4)
- [ ] `dbt_project/dbt_project.yml` (Etapa 4)

**Saídas pré-carregadas no terminal/navegador**
- [ ] Página do GitHub Actions aberta com os 4 jobs verdes (lint, dag-tests, dbt-parse, meltano-config)
- [ ] Saída do pytest (`41 passed, 31 deselected`) — copiar/colar antes de gravar

**Geral**
- [ ] Terminal com fonte legível (mínimo 16pt), fundo escuro
- [ ] Janela do Airflow em 100% de zoom para legibilidade
- [ ] Microfone testado
- [ ] Gravador de tela pronto (Loom, OBS ou QuickTime)

---

## Referência de tempo

| Etapa | Conteúdo | Tempo |
|---|---|---|
| 1 | Apresentação + arquitetura | 0:00 – 0:30 |
| 2 | Deploy no Kubernetes (kubectl ao vivo) | 0:30 – 1:15 |
| 3 | Airflow: topologia + gate + execução verde | 1:15 – 2:15 |
| 4 | Meltano + dbt: configs de ingestão e transformação | 2:15 – 3:05 |
| 5 | Dados no destino (DBeaver — schemas e tabelas) | 3:05 – 3:35 |
| 6 | CI (GitHub Actions) + pytest + dbt tests | 3:35 – 4:25 |
| 7 | Metabase (breve) + encerramento | 4:25 – 4:50 |
