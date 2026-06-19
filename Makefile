.PHONY: help up down build logs-airflow meltano-install start \
        kind-up kind-load kind-deploy kind-down kind-start kind-upgrade \
        kind-secrets kind-admin-password kind-test \
        dbt-run dbt-test lint lint-sql fix-sql test test-integration

COMPOSE = docker compose
KIND_CLUSTER = banvic
IMAGE_NAME = banvic-airflow
IMAGE_TAG  = latest
AIRFLOW_CHART_VERSION = 1.13.0
AIRFLOW_CHART_URL = https://github.com/apache/airflow/releases/download/helm-chart%2F$(AIRFLOW_CHART_VERSION)/airflow-$(AIRFLOW_CHART_VERSION).tgz
AIRFLOW_CHART_TGZ = /tmp/airflow-$(AIRFLOW_CHART_VERSION).tgz

help:
	@echo ""
	@echo "BanVic ELT - Comandos disponíveis"
	@echo "================================="
	@echo ""
	@echo "Atalhos (ambiente já configurado):"
	@echo "  make start             sobe todo o ambiente Docker Compose"
	@echo "  make kind-start        sobe todo o ambiente Kubernetes do zero"
	@echo ""
	@echo "Docker Compose (dev):"
	@echo "  make up                build + docker compose up"
	@echo "  make down              derruba e remove volumes"
	@echo "  make build             reconstrói a imagem Airflow"
	@echo "  make logs-airflow      logs do scheduler/webserver"
	@echo "  make meltano-install   instala plugins do Meltano no projeto"
	@echo ""
	@echo "Kubernetes / Kind (entrega):"
	@echo "  make kind-up             cria o cluster Kind"
	@echo "  make kind-load           constrói e carrega a imagem no Kind"
	@echo "  make kind-secrets        gera k8s/secrets.yaml a partir do .env"
	@echo "  make kind-deploy         aplica os manifests + instala Airflow via Helm"
	@echo "  make kind-admin-password cria o usuário admin com a senha do .env"
	@echo "  make kind-upgrade        aplica mudanças do values.yaml via helm upgrade"
	@echo "  make kind-test           41 testes unitários no pod do scheduler Kind"
	@echo "  make kind-down           destrói o cluster Kind"
	@echo ""
	@echo "Transformação / Testes:"
	@echo "  make dbt-run           roda o dbt no container dbt"
	@echo "  make dbt-test          testa os modelos dbt"
	@echo "  make lint              ruff + yamllint + sqlfluff"
	@echo "  make lint-sql          sqlfluff lint nos modelos dbt"
	@echo "  make fix-sql           sqlfluff fix (auto-corrige estilo SQL)"
	@echo "  make test              testes unitários (no container)"
	@echo "  make test-integration  testes de integração (requer make up)"
	@echo ""

# ---------- Atalhos (ambiente já configurado) ----------

start: up

kind-start: kind-up kind-load kind-secrets kind-deploy
	@echo "Aguardando webserver e scheduler ficarem prontos (pode levar ~3 min)..."
	kubectl rollout status deployment/airflow-webserver -n banvic --timeout=300s
	kubectl rollout status deployment/airflow-scheduler -n banvic --timeout=300s
	$(MAKE) kind-admin-password
	@echo ""
	@echo "OK: ambiente Kubernetes no ar."
	@echo "    Airflow:  http://localhost:8080  (admin / AIRFLOW_ADMIN_PASSWORD do .env)"
	@echo "    Metabase: http://localhost:3000"
	@echo "    Dispare a DAG: Airflow UI → banvic_elt → botão ▶ Trigger DAG"

# ---------- Docker Compose ----------

build:
	$(COMPOSE) build airflow-webserver

up: build
	@test -f .env || (echo "ERRO: arquivo .env não encontrado. Copie .env.example para .env e preencha." && exit 1)
	$(COMPOSE) up -d
	@echo "OK: ambiente subindo. Airflow: http://localhost:8080  Metabase: http://localhost:3000"

down:
	$(COMPOSE) down -v

logs-airflow:
	$(COMPOSE) logs -f airflow-webserver airflow-scheduler

# ---------- Meltano ----------

meltano-install:
	cd meltano && meltano install

# ---------- dbt ----------

dbt-run:
	$(COMPOSE) exec dbt dbt run --profiles-dir /usr/app/dbt --project-dir /usr/app/dbt

dbt-test:
	$(COMPOSE) exec dbt dbt test --profiles-dir /usr/app/dbt --project-dir /usr/app/dbt

# ---------- Linting ----------

lint:
	ruff check dags/ tests/
	ruff format --check dags/ tests/
	yamllint -c .yamllint meltano/meltano.yml docker-compose.yml
	sqlfluff lint dbt_project/models

lint-sql:
	sqlfluff lint dbt_project/models

fix-sql:
	sqlfluff fix dbt_project/models

AIRFLOW_PYTEST = PYTHONPATH=/home/airflow/.local/lib/python3.12/site-packages \
	$(COMPOSE) exec airflow-scheduler \
	/home/airflow/tool-venv/bin/python -m pytest

test:
	@$(COMPOSE) exec airflow-scheduler /home/airflow/tool-venv/bin/pip install pytest pyyaml psycopg2-binary -q
	$(AIRFLOW_PYTEST) tests/ -m "not integration" -v

test-integration:
	@echo "AVISO: requer make up e a DAG executada ao menos uma vez."
	@$(COMPOSE) exec airflow-scheduler /home/airflow/tool-venv/bin/pip install pytest pyyaml psycopg2-binary -q
	$(AIRFLOW_PYTEST) -m integration -v

kind-test:
	@POD=$$(kubectl get pod -n banvic -l component=scheduler -o jsonpath='{.items[0].metadata.name}') && \
	echo "Copiando arquivos de teste para $$POD..." && \
	kubectl exec -n banvic $$POD -c scheduler -- rm -rf /tmp/tests /tmp/dbt_project /tmp/meltano /tmp/pyproject.toml && \
	kubectl cp tests/         banvic/$$POD:/tmp/tests         -c scheduler && \
	kubectl cp dbt_project/   banvic/$$POD:/tmp/dbt_project   -c scheduler && \
	kubectl cp meltano/       banvic/$$POD:/tmp/meltano       -c scheduler && \
	kubectl cp pyproject.toml banvic/$$POD:/tmp/pyproject.toml -c scheduler && \
	kubectl exec -n banvic $$POD -c scheduler -- \
		/home/airflow/tool-venv/bin/pip install pytest pyyaml -q && \
	kubectl exec -n banvic $$POD -c scheduler -- \
		bash -c "cd /tmp && PYTHONPATH=/home/airflow/.local/lib/python3.12/site-packages \
		/home/airflow/tool-venv/bin/python -m pytest tests/ -m 'not integration' -v"

# ---------- Kind (Kubernetes local) ----------

kind-admin-password:
	@test -f .env || (echo "ERRO: .env não encontrado." && exit 1)
	@set -a && . ./.env && set +a && \
	POD=$$(kubectl get pods -n banvic -l component=webserver -o jsonpath='{.items[0].metadata.name}') && \
	kubectl exec -n banvic $$POD -- airflow users create \
		--username admin \
		--password "$$AIRFLOW_ADMIN_PASSWORD" \
		--firstname Admin \
		--lastname BanVic \
		--role Admin \
		--email admin@banvic.local && \
	echo "OK: usuário admin criado com AIRFLOW_ADMIN_PASSWORD do .env"

kind-secrets:
	@test -f .env || (echo "ERRO: .env não encontrado. Copie .env.example para .env e preencha." && exit 1)
	bash scripts/generate-k8s-secrets.sh

kind-up:
	kind create cluster --config k8s/kind-cluster.yaml
	kubectl cluster-info --context kind-$(KIND_CLUSTER)

kind-load: build
	docker tag de_enginerr_cert_ind-airflow-webserver:latest $(IMAGE_NAME):$(IMAGE_TAG)
	kind load docker-image $(IMAGE_NAME):$(IMAGE_TAG) --name $(KIND_CLUSTER)
	@echo "OK: imagem $(IMAGE_NAME):$(IMAGE_TAG) carregada no cluster $(KIND_CLUSTER)."

kind-deploy:
	kubectl apply -f k8s/namespace.yaml
	@if [ ! -f k8s/secrets.yaml ]; then \
		echo "ERRO: k8s/secrets.yaml não encontrado. Execute 'make kind-secrets' antes de continuar." && exit 1; \
	fi
	kubectl apply -f k8s/secrets.yaml -n banvic
	kubectl apply -f k8s/postgres/ -n banvic
	kubectl apply -f k8s/airflow/airflow-db-statefulset.yaml -n banvic
	kubectl apply -f k8s/metabase/ -n banvic
	@echo "Criando diretórios no nó Kind e corrigindo permissões..."
	docker exec $(KIND_CLUSTER)-control-plane mkdir -p /tmp/airflow-logs
	docker exec $(KIND_CLUSTER)-control-plane chown -R 50000:0 /tmp/airflow-logs
	docker exec $(KIND_CLUSTER)-control-plane chmod -R 775 /tmp/airflow-logs
	docker exec $(KIND_CLUSTER)-control-plane mkdir -p /mnt/landing-data
	docker exec $(KIND_CLUSTER)-control-plane chmod 777 /mnt/landing-data
	kubectl apply -f k8s/airflow/logs-pv.yaml
	@echo "Aguardando airflow-db ficar pronto (até 3 min)..."
	kubectl wait --for=condition=ready pod/airflow-db-0 -n banvic --timeout=180s
	@echo "Baixando chart do Airflow $(AIRFLOW_CHART_VERSION)..."
	curl -sSL -o $(AIRFLOW_CHART_TGZ) $(AIRFLOW_CHART_URL)
	helm install airflow $(AIRFLOW_CHART_TGZ) -n banvic -f k8s/airflow/values.yaml --timeout 10m
	rm -f $(AIRFLOW_CHART_TGZ)
	@echo "OK: deploy concluído — namespace, secrets, postgres, airflow-db, metabase e Airflow aplicados."
	@echo "    Aguarde os pods ficarem 1/1 Running: kubectl get pods -n banvic -w"

kind-upgrade:
	@echo "Garantindo PV de logs e permissões no nó Kind..."
	docker exec $(KIND_CLUSTER)-control-plane mkdir -p /tmp/airflow-logs
	docker exec $(KIND_CLUSTER)-control-plane chown -R 50000:0 /tmp/airflow-logs
	docker exec $(KIND_CLUSTER)-control-plane chmod -R 775 /tmp/airflow-logs
	kubectl apply -f k8s/airflow/logs-pv.yaml
	@echo "Baixando chart do Airflow $(AIRFLOW_CHART_VERSION)..."
	curl -sSL -o $(AIRFLOW_CHART_TGZ) $(AIRFLOW_CHART_URL)
	helm upgrade airflow $(AIRFLOW_CHART_TGZ) -n banvic -f k8s/airflow/values.yaml
	rm -f $(AIRFLOW_CHART_TGZ)
	@echo "OK: Airflow atualizado. Aguarde os pods reiniciarem: kubectl get pods -n banvic -w"

kind-down:
	kind delete cluster --name $(KIND_CLUSTER)
