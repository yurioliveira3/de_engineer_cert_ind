{% macro populate_test_results() %}
    {#
        Persiste os resultados reais de `dbt test` em metadata.test_results.
        Usa a variável `results` disponível no contexto on-run-end - contém
        status real (pass/fail/warn/error) de cada teste executado.
    #}
    {% if execute and flags.WHICH == 'test' %}
        {% for result in results %}
            {% if result.node.resource_type == 'test' %}
                {% set model = result.node.depends_on.nodes[0].split('.')[-1]
                               if result.node.depends_on.nodes else 'unknown' %}
                {% set col = result.node.column_name or 'N/A' %}
                {% set msg = (result.message | string | replace("'", "''"))
                             if result.message else '' %}
                {% set sql %}
                    INSERT INTO metadata.test_results
                        (test_name, model_name, column_name, status, message)
                    VALUES (
                        '{{ result.node.name | replace("'", "''") }}',
                        '{{ model | replace("'", "''") }}',
                        '{{ col | replace("'", "''") }}',
                        '{{ result.status }}',
                        '{{ msg }}'
                    )
                {% endset %}
                {% do run_query(sql) %}
            {% endif %}
        {% endfor %}
    {% endif %}
{% endmacro %}
