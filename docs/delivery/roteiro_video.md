# Roteiro do Vídeo - BanVic ELT Pipeline

**Duração total:** 4:30 - 4:45 minutos  
**Formato:** screen recording + narração  
**Estrutura:** 6 etapas faseadas, cada uma com o que mostrar na tela e o que falar

> **Dica de gravação:** rode `make up` e dispare a DAG **antes** de começar a gravar.
> Mostre resultados já prontos — execução em tempo real dentro de um vídeo de 5 min
> não é viável. A única exceção é o pytest (Etapa 5), que roda rápido.

---

## Etapa 1 — Apresentação e Arquitetura `[0:00 - 0:40]`

**O que mostrar na tela**
- Abra `docs/architectures/arquitetura_dados.drawio` no draw.io (ou a imagem exportada)
- Aponte com o cursor para as zonas à medida que fala

**O que falar**
> "Olá, apresento o case BanVic — uma pipeline ELT completa desenvolvida como
> entregável da Certificação Data Engineer da Indicium.
>
> O projeto cobre toda a stack: **ingestão com Meltano** extraindo dados de um PostgreSQL
> simulando um ERP bancário e de um arquivo CSV de transações; **orquestração com Apache
> Airflow**; **transformação com dbt** em três camadas — bronze, silver e gold; e
> **Metabase** para visualização. Tudo roda em Docker Compose para desenvolvimento e em
> Kubernetes com Kind para produção. Vamos ver isso funcionando."

---

## Etapa 2 — Deploy do Ambiente `[0:40 - 1:20]`

**O que mostrar na tela**
1. Terminal na raiz do projeto — mostre o resultado já rodando: `docker compose ps`
2. Abra brevemente o `.env.example` para mostrar a estratégia de segredos

**O que falar**
> "Com um único comando — `make up` — o ambiente completo sobe: source Postgres com os
> dados do ERP, o Data Warehouse, o Airflow, o Meltano, o dbt e o Metabase.
>
> **Nenhuma credencial está no código.** Senhas e chaves ficam no `.env`, que está no
> `.gitignore`. O Airflow recebe suas conexões via variável de ambiente `AIRFLOW_CONN_*`
> — sem configuração manual na UI, sem segredo em repositório."

```bash
docker compose ps
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
> Todas as tasks têm retries com backoff exponencial e um `on_failure_callback` que loga
> erros estruturados."

---

## Etapa 4 — Dados no Destino `[2:30 - 3:20]`

**O que mostrar na tela**
1. Terminal com psql no DW — tabelas raw (Bronze)
2. Query nos marts de negócio (Gold) — narrativa Camila + CEO

**O que falar**
> "Com a DAG verde, os dados chegaram no destino. Vou consultar o Data Warehouse."

```bash
# Camada Bronze — raw (saída do Meltano, FULL_TABLE)
docker compose exec dw-postgres psql -U analytics -d analytics_dw \
  -c "SELECT schemaname, tablename, n_live_tup
      FROM pg_stat_user_tables
      WHERE schemaname = 'raw'
      ORDER BY tablename;"
```

> "7 tabelas na camada bronze, populadas com FULL_TABLE — o que garante idempotência:
> rodar a DAG duas vezes no mesmo dia produz exatamente o mesmo resultado, sem duplicação.
>
> Na camada gold, os marts de negócio respondem perguntas concretas. Para a Camila,
> gerente comercial: quais clientes estão em risco de churn?"

```bash
# Narrativa Camila — engajamento e risco de churn
docker compose exec dw-postgres psql -U analytics -d analytics_dw \
  -c "SELECT engagement_status, COUNT(*) AS clientes
      FROM marts.mart_engajamento_cliente
      GROUP BY 1 ORDER BY 2 DESC;"

# Narrativa CEO Sofia — quais alavancas movem o ponteiro?
docker compose exec dw-postgres psql -U analytics -d analytics_dw \
  -c "SELECT driver, correlation, significant_at_5pct, impact_rank
      FROM marts.mart_ranking_alavancas
      ORDER BY impact_rank;"
```

> "E para a CEO Sofia: um ranking de correlação de Pearson entre cada driver candidato
> e o número de transações por cliente — com t-statistic para significância estatística."

---

## Etapa 5 — Qualidade e Testes `[3:20 - 4:05]`

**O que mostrar na tela**
1. Terminal com os testes pytest rodando — deixe a saída aparecer
2. Mostre o resultado: `41 passed, 31 deselected`

**O que falar**
> "O projeto tem 72 testes automatizados: 41 unitários e 31 de integração, cobrindo
> topologia da DAG, resiliência a falhas, configuração do Meltano, governança dos
> modelos dbt e integridade dos dados.
>
> Os 41 testes de unidade rodam no CI via GitHub Actions a cada push — sem banco.
> Os 31 de integração rodam contra o banco real via `make test-integration`."

```bash
# testes unitários (sem banco, rápidos)
docker compose exec airflow-scheduler \
  /home/airflow/tool-venv/bin/python -m pytest tests/ -m "not integration" -q
```

> "Além desses, o dbt executa mais 69 data tests na etapa `dbt_test` — dois deles falham
> intencionalmente, capturando uma inconsistência real de integridade referencial no dado
> fonte. Isso demonstra que a camada Silver detecta defeitos antes de contaminar a Gold."

---

## Etapa 6 — Kubernetes e Encerramento `[4:05 - 4:45]`

**O que mostrar na tela**
1. Terminal com `kubectl get pods -n banvic` (cluster já rodando)
2. Feche com o `README.md` aberto

**O que falar**
> "Para produção, o mesmo pipeline roda em Kubernetes local com Kind. Os manifests em
> `k8s/` cobrem namespace, Kubernetes Secrets, StatefulSets para os três bancos Postgres
> com PVCs, Deployment do Metabase, e o Airflow via Helm chart com KubernetesExecutor.
> Os dados são montados via `extraMounts` do Kind — o pipeline roda end-to-end também
> no cluster, não só no Compose.
>
> Para mais detalhes, prints das execuções, diagramas de arquitetura e o passo a passo
> completo de replicação, acesse o `README.md` do repositório. Obrigado!"

```bash
kubectl get pods -n banvic
```

---

## Checklist antes de gravar

- [ ] `make up` rodado, todos os containers `healthy` (`docker compose ps`)
- [ ] DAG `banvic_elt` com pelo menos uma execução verde no histórico
- [ ] Metabase configurado e com um dashboard básico visível (opcional)
- [ ] Terminal com fonte legível (mínimo 16pt), fundo escuro
- [ ] Janela do Airflow em 100% de zoom para legibilidade
- [ ] Microfone testado
- [ ] Gravador de tela pronto (Loom, OBS ou QuickTime)

---

## Referência de tempo

| Etapa | Conteúdo | Tempo |
|---|---|---|
| 1 | Apresentação + arquitetura | 0:00 – 0:40 |
| 2 | Deploy (`make up`) + segredos | 0:40 – 1:20 |
| 3 | Airflow: topologia + gate + execução verde | 1:20 – 2:30 |
| 4 | Bronze raw + marts Camila + ranking CEO | 2:30 – 3:20 |
| 5 | Pytest 41 unit + 2 falhas esperadas no dbt | 3:20 – 4:05 |
| 6 | Kind/K8s + encerramento | 4:05 – 4:45 |
