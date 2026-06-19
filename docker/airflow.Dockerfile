FROM apache/airflow:2.9.2

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Provider Postgres para Airflow 2.9.x (sem atualizar o core)
RUN pip install --no-cache-dir "apache-airflow-providers-postgres~=5.10"

# Meltano + dbt em venv isolado -> evita conflito de SQLAlchemy (Airflow 2.9 usa 1.x; Meltano 3.7+ exige 2.x)
RUN python3 -m venv /home/airflow/tool-venv && \
    /home/airflow/tool-venv/bin/pip install --no-cache-dir \
        "meltano>=3.7.0,<4" \
        "dbt-core>=1.8.0,<2" \
        "dbt-postgres>=1.8.0,<2"

# Coloca o venv no PATH para BashOperator encontrar meltano e dbt
ENV PATH="/home/airflow/tool-venv/bin:/home/airflow/.local/bin:${PATH}"

# Bake DAGs e projeto Meltano/dbt na imagem (para deploy K8s sem hostPath)
COPY --chown=airflow:root dags/ /opt/airflow/dags/
COPY --chown=airflow:root meltano/ /opt/airflow/meltano/
COPY --chown=airflow:root dbt_project/ /opt/airflow/dbt_project/
