-- =============================================================================
-- 02 · Visão geral do negócio
-- Quanto a loja vende, como as vendas evoluem e quem compra.
-- Rodar: python rodar_sql.py sql/02_visao_geral.sql --csv
-- Observação: a base vai de 01/12/2009 a 09/12/2011. Dezembro de 2011 está
-- incompleto, por isso as comparações anuais usam janeiro a novembro.
-- =============================================================================

-- nome: Indicadores gerais
SELECT
    ROUND(SUM(receita), 2)                          AS receita_total,
    COUNT(DISTINCT fatura)                          AS pedidos,
    COUNT(DISTINCT id_cliente)                      AS clientes,
    ROUND(SUM(receita) / COUNT(DISTINCT fatura), 2) AS ticket_medio,
    SUM(quantidade)                                 AS unidades_vendidas
FROM vendas;

-- nome: Comparação 2010 x 2011 (janeiro a novembro)
SELECT
    year(data)                                      AS ano,
    ROUND(SUM(receita), 2)                          AS receita,
    COUNT(DISTINCT fatura)                          AS pedidos,
    COUNT(DISTINCT id_cliente)                      AS clientes,
    ROUND(SUM(receita) / COUNT(DISTINCT fatura), 2) AS ticket_medio
FROM vendas
WHERE month(data) BETWEEN 1 AND 11
  AND year(data) IN (2010, 2011)
GROUP BY ano
ORDER BY ano;

-- nome: Receita por mês
-- LAG pega o valor do mesmo mês no ano anterior para calcular o crescimento
WITH mensal AS (
    SELECT
        date_trunc('month', data)   AS mes,
        SUM(receita)                AS receita,
        COUNT(DISTINCT fatura)      AS pedidos
    FROM vendas
    WHERE data < DATE '2011-12-01'
    GROUP BY mes
)
SELECT
    strftime(mes, '%Y-%m')                                          AS mes,
    ROUND(receita, 0)                                               AS receita,
    pedidos,
    ROUND(100.0 * (receita / LAG(receita, 12) OVER (ORDER BY mes) - 1), 1) AS cresc_vs_ano_anterior_pct
FROM mensal
ORDER BY mes;

-- nome: Receita por dia da semana
SELECT
    dayname(data)                                   AS dia_semana,
    ROUND(SUM(receita), 0)                          AS receita,
    COUNT(DISTINCT fatura)                          AS pedidos,
    ROUND(100.0 * SUM(receita) / SUM(SUM(receita)) OVER (), 1) AS pct_receita
FROM vendas
GROUP BY dia_semana, isodow(data)
ORDER BY isodow(data);

-- nome: Receita por país (fora o Reino Unido)
SELECT
    pais,
    ROUND(SUM(receita), 0)                          AS receita,
    COUNT(DISTINCT id_cliente)                      AS clientes,
    ROUND(SUM(receita) / COUNT(DISTINCT fatura), 2) AS ticket_medio
FROM vendas
WHERE pais <> 'United Kingdom'
GROUP BY pais
ORDER BY receita DESC
LIMIT 10;
