# Roteiro do Vídeo - BanVic ELT Pipeline

**Duração total:** 4:35 - 4:45 minutos
**Formato:** screen recording + narração
**Ambiente:** Kubernetes local com Kind (KubernetesExecutor)
**Estrutura:** 7 etapas faseadas, cada uma com o que mostrar na tela e o que falar

> **Dica de gravação:** rode `make kind-start` e dispare a DAG **antes** de começar a gravar.
> Mostre resultados já prontos — execução em tempo real dentro de um vídeo de 5 min
> não é viável. A única exceção é o pytest (Etapa 6), que roda rápido.

---

## Etapa 1 — Apresentação e Arquitetura `[0:00 - 0:35]`

**O que mostrar na tela**
- Abra `docs/architectures/arquitetura_dados.drawio` no draw.io (ou a imagem exportada)
- Aponte com o cursor para as zonas à medida que fala

**O que falar**
> "Olá, apresento o case BanVic — uma pipeline ELT completa desenvolvida como
> entregável da Certificação Data Engineer da Indicium.
>
> O projeto cobre toda a stack: **ingestão com Meltano** extraindo dados de um PostgreSQL
> simulando um ERP bancário e de um arquivo CSV de transações; **orquestração com Apache
> Airflow** rodando em **Kubernetes** com KubernetesExecutor; **transformação com dbt** em
> três camadas — bronze, silver e gold; e **Metabase** para visualização. Tudo roda em
> Kubernetes local com Kind. Vamos ver isso funcionando."

---

## Etapa 2 — Deploy no Kubernetes `[0:35 - 1:20]`

**O que mostrar na tela**
1. Terminal — mostre o cluster já rodando: `kubectl get pods -n banvic`
2. Abra brevemente o `.env.example` para mostrar a origem dos segredos

**O que falar**
> "O ambiente completo sobe em Kubernetes local com Kind — um único comando `make
> kind-start` cria o cluster, constrói a imagem, gera os Secrets e aplica todos os
> manifests.
>
> Aqui estão os pods: source-postgres com os dados do ERP, o Data Warehouse,
> o Metabase, e o Airflow com scheduler, webserver e triggerer — todos Running.
>
> **Nenhuma credencial está no código.** As senhas partem do `.env` — que está no
> `.gitignore` — e são convertidas em Kubernetes Secrets via `make kind-secrets`.
> O Airflow recebe suas conexões via `secretKeyRef` — sem configuração manual na UI,
> sem segredo em repositório."

```bash
kubectl get pods -n banvic
```

---

## Etapa 3 — Orquestração: DAG no Airflow `[1:20 - 2:30]`

**O que mostrar na tela**
1. Abra `http://localhost:8080` — Airflow UI
2. Navegue até a DAG `banvic_elt` → **Graph View** para mostrar a topologia
3. Mostre uma execução já verde no histórico
4. Clique em `validate_raw_load` → **Logs** — mostre as 7 contagens passando

**O que falar**
> "Aqui está a DAG `banvic_elt`. A topologia implementa boas práticas de orquestração:
>
> Começa com um **FileSensor** que bloqueia até o arquivo de transações estar disponível.
> Em paralelo, o Meltano extrai as 6 tabelas do ERP via `tap-postgres` e o CSV via
> `tap-csv` — as duas cargas rodam simultaneamente.
>
> Antes de qualquer transformação, temos um **gate de validação** — o `validate_raw_load`
> — que confirma que as 7 tabelas `raw.*` foram populadas. Se alguma estiver vazia, o
> pipeline falha aqui com erro claro, antes de gastar processamento com o dbt. Só então
> o dbt roda: transformações e depois testes de qualidade.
>
> Como usamos **KubernetesExecutor**, cada uma dessas tasks executou como um pod isolado
> no cluster — isolamento completo entre as etapas. Todas as tasks têm retries com
> backoff exponencial e um `on_failure_callback` que loga erros estruturados."

---

## Etapa 4 — Dados no Destino `[2:30 - 2:55]`

**O que mostrar na tela**
1. Terminal com `kubectl exec` no DW — tabelas raw (Bronze)

**O que falar**
> "Com a DAG verde, os dados chegaram no destino. Vou consultar o Data Warehouse
> direto no pod do Postgres."

```bash
# Camada Bronze — raw (saída do Meltano, FULL_TABLE)
kubectl exec -n banvic dw-postgres-0 -- psql -U analytics -d analytics_dw \
  -c "SELECT schemaname, tablename, n_live_tup
      FROM pg_stat_user_tables
      WHERE schemaname = 'raw'
      ORDER BY tablename;"
```

> "7 tabelas na camada bronze, populadas com FULL_TABLE — o que garante idempotência:
> rodar a DAG duas vezes produz exatamente o mesmo resultado, sem duplicação. Na
> sequência, o dbt transformou esses dados em marts de negócio na camada gold —
> que veremos agora no Metabase."

---

## Etapa 5 — Visualização no Metabase `[2:55 - 3:35]`

**O que mostrar na tela**
1. Abra `http://localhost:3000` — Metabase
2. Mostre o dashboard comercial com o gráfico de distribuição de engajamento
3. Abra a pergunta do ranking de alavancas (native query)

**O que falar**
> "Os marts da camada Gold ficam disponíveis para consumo direto no Metabase — a
> ferramenta de BI escolhida pelo BanVic. Aqui está o dashboard comercial que atende
> o pedido da CEO Sofia: a distribuição de clientes por status de engajamento —
> ativos, em risco, churned e sem uso — base para a campanha de retenção da Camila.
>
> E o ranking de alavancas: cada driver com sua correlação de Pearson e flag de
> significância estatística. O Metabase consome direto do schema `marts` — sem
> camada intermediária, sem planilha, sem export manual."

---

## Etapa 6 — Qualidade e Testes `[3:35 - 4:20]`

**O que mostrar na tela**
1. Terminal com `make kind-test` rodando — deixe a saída aparecer
2. Mostre o resultado: `41 passed, 31 deselected`

**O que falar**
> "O projeto tem 72 testes automatizados: 41 unitários e 31 de integração, cobrindo
> topologia da DAG, resiliência a falhas, configuração do Meltano, governança dos
> modelos dbt e integridade dos dados.
>
> Os 41 testes de unidade rodam no CI via GitHub Actions a cada push — sem banco.
> Aqui no cluster eu rodo direto no pod do scheduler:"

```bash
make kind-test
```

> "Além desses, o dbt executa mais 69 data tests na etapa `dbt_test` — dois deles
> geram alerta (`severity: warn`), capturando uma inconsistência real de integridade
> referencial no dado fonte: o cliente 528 existe em contas e propostas de crédito,
> mas não no cadastro de clientes. O pipeline não é interrompido, mas o defeito fica
> registrado em `metadata.test_results` e visível no dashboard de qualidade. Isso
> demonstra que a camada Silver detecta defeitos antes de contaminar a Gold."

---

## Etapa 7 — Encerramento `[4:20 - 4:45]`

**O que mostrar na tela**
1. Feche com o `README.md` aberto

**O que falar**
> "Isso cobre o pipeline completo: ingestão com Meltano, orquestração com Airflow em
> Kubernetes, transformação com dbt em arquitetura Medallion, visualização no Metabase
> e qualidade assegurada por 72 testes automatizados.
>
> Para mais detalhes, diagramas de arquitetura e o passo a passo completo de
> replicação — tanto em Docker Compose quanto em Kubernetes — acesse o `README.md`
> do repositório. Obrigado!"

---

## Checklist antes de gravar

**Kubernetes / Kind**
- [ ] Cluster Kind no ar (`kubectl get pods -n banvic` todos `Running`)
- [ ] `make kind-start` executado com sucesso (cluster → imagem → secrets → deploy → admin)
- [ ] `make kind-upgrade` aplicado (configura PV de logs — sem isso os logs das tasks não aparecem na UI)
- [ ] DAG `banvic_elt` executada e verde no histórico
- [ ] Logs da task `validate_raw_load` visíveis na UI (confirma que os dados chegaram)
- [ ] Testes validados: `make kind-test` → `41 passed`

**Metabase**
- [ ] Metabase configurado (`http://localhost:3000`) com conexão ao DW `analytics_dw`
- [ ] Dashboard comercial visível com o gráfico de engajamento (`mart_engajamento_cliente`)
- [ ] Pergunta do ranking de alavancas criada (`mart_ranking_alavancas`)

**Geral**
- [ ] Terminal com fonte legível (mínimo 16pt), fundo escuro
- [ ] Janela do Airflow em 100% de zoom para legibilidade
- [ ] Microfone testado
- [ ] Gravador de tela pronto (Loom, OBS ou QuickTime)

---

## Referência de tempo

| Etapa | Conteúdo | Tempo |
|---|---|---|
| 1 | Apresentação + arquitetura | 0:00 – 0:35 |
| 2 | Deploy no Kubernetes (Kind) + segredos | 0:35 – 1:20 |
| 3 | Airflow: topologia + KubernetesExecutor + execução verde | 1:20 – 2:30 |
| 4 | Bronze raw (kubectl exec psql) — só contagem | 2:30 – 2:55 |
| 5 | Metabase: dashboard engajamento + ranking CEO | 2:55 – 3:35 |
| 6 | Pytest 41 unit (make kind-test) + 2 warns esperados no dbt | 3:35 – 4:20 |
| 7 | Encerramento (recap + README) | 4:20 – 4:45 |
