-- =============================================================================
-- 06 · Devoluções
-- Quanto volta em devolução, quais produtos mais voltam e quando?
-- Taxa de devolução = o que foi devolvido ÷ o que foi vendido.
-- Rodar: python rodar_sql.py sql/06_devolucoes.sql --csv
--
-- Dois pedidos gigantes foram cancelados inteiros logo depois da venda
-- (80.995 e 74.215 unidades de um único produto). Eles parecem erro de digitação
-- ou pedido de teste, não uma devolução de cliente, e sozinhos somam um terço
-- de todo o valor devolvido. Por isso as análises por produto e por mês os separam.
-- =============================================================================

-- nome: Cria a visão devolucoes_comuns (sem os dois cancelamentos gigantes)
-- Uma VIEW é uma consulta salva com nome: não copia os dados, só os filtra na hora.
CREATE OR REPLACE VIEW devolucoes_comuns AS
SELECT *
FROM devolucoes
WHERE valor_devolvido < 50000;

-- nome: Visão geral das devoluções
WITH totais AS (
    SELECT
        (SELECT SUM(receita) FROM vendas)                       AS vendido,
        (SELECT SUM(valor_devolvido) FROM devolucoes)           AS devolvido_total,
        (SELECT SUM(valor_devolvido) FROM devolucoes_comuns)    AS devolvido_comum,
        (SELECT COUNT(DISTINCT fatura) FROM devolucoes)         AS faturas_devolucao,
        (SELECT COUNT(DISTINCT fatura) FROM vendas)             AS faturas_venda
)
SELECT
    ROUND(devolvido_total, 0)                                   AS valor_devolvido,
    ROUND(100 * devolvido_total / vendido, 2)                   AS taxa_devolucao_pct,
    ROUND(devolvido_total - devolvido_comum, 0)                 AS dois_cancelamentos_gigantes,
    ROUND(100 * (devolvido_total - devolvido_comum) / devolvido_total, 1) AS pct_do_devolvido,
    ROUND(100 * devolvido_comum / vendido, 2)                   AS taxa_sem_gigantes_pct,
    faturas_devolucao,
    ROUND(100.0 * faturas_devolucao / faturas_venda, 1)         AS faturas_devolucao_por_100_vendas
FROM totais;

-- nome: Devoluções que parecem correção de pedido
-- Muitas "devoluções" não são cliente insatisfeito: o pedido foi lançado errado,
-- cancelado e refeito. Regra aproximada: o mesmo cliente comprou a mesma quantidade
-- do mesmo produto até 1 dia antes ou depois da devolução.
WITH marcadas AS (
    SELECT
        d.valor_devolvido,
        EXISTS (
            SELECT 1
            FROM vendas v
            WHERE v.id_cliente = d.id_cliente
              AND v.codigo_produto = d.codigo_produto
              AND v.quantidade = d.quantidade_devolvida
              AND abs(date_diff('day', v.data, d.data)) <= 1
        ) AS parece_correcao
    FROM devolucoes_comuns d
    WHERE d.id_cliente IS NOT NULL
)
SELECT
    CASE WHEN parece_correcao THEN 'parece correção de pedido' ELSE 'devolução de cliente' END AS tipo,
    COUNT(*)                                                        AS linhas,
    ROUND(SUM(valor_devolvido), 0)                                  AS valor,
    ROUND(100 * SUM(valor_devolvido) / SUM(SUM(valor_devolvido)) OVER (), 1) AS pct_valor
FROM marcadas
GROUP BY tipo
ORDER BY valor DESC;

-- nome: Produtos com maior taxa de devolução
-- Filtros para achar problema recorrente, e não acaso ou correção pontual:
--   * mais de 1.000 unidades vendidas (senão um item que vendeu 2 e voltou 1 teria 50%);
--   * devolvido em pelo menos 5 pedidos diferentes (uma correção única de pedido
--     grande gera taxas perto de 50% que não dizem nada sobre o produto).
WITH vendido AS (
    SELECT codigo_produto, SUM(quantidade) AS unidades_vendidas, SUM(receita) AS receita
    FROM vendas
    GROUP BY codigo_produto
    HAVING SUM(quantidade) > 1000
),
devolvido AS (
    SELECT
        codigo_produto,
        SUM(quantidade_devolvida)   AS unidades_devolvidas,
        SUM(valor_devolvido)        AS valor_devolvido,
        COUNT(DISTINCT fatura)      AS devolucoes
    FROM devolucoes_comuns
    GROUP BY codigo_produto
)
SELECT
    v.codigo_produto,
    p.descricao,
    v.unidades_vendidas,
    d.unidades_devolvidas,
    ROUND(100.0 * d.unidades_devolvidas / v.unidades_vendidas, 1)   AS taxa_devolucao_pct,
    d.devolucoes                                                    AS vezes_devolvido,
    ROUND(d.valor_devolvido, 0)                                     AS valor_devolvido
FROM vendido v
JOIN devolvido d USING (codigo_produto)
LEFT JOIN produtos p USING (codigo_produto)
WHERE d.devolucoes >= 5
ORDER BY taxa_devolucao_pct DESC
LIMIT 15;

-- nome: Produtos que mais custam em devolução (valor)
SELECT
    d.codigo_produto,
    p.descricao,
    ROUND(SUM(d.valor_devolvido), 0)        AS valor_devolvido,
    SUM(d.quantidade_devolvida)             AS unidades_devolvidas,
    COUNT(DISTINCT d.fatura)                AS vezes_devolvido,
    a.classe                                AS classe_abc
FROM devolucoes_comuns d
LEFT JOIN produtos p USING (codigo_produto)
LEFT JOIN curva_abc a USING (codigo_produto)
GROUP BY d.codigo_produto, p.descricao, a.classe
ORDER BY valor_devolvido DESC
LIMIT 10;

-- nome: Taxa de devolução por classe ABC
SELECT
    a.classe,
    ROUND(SUM(a.receita), 0)                                         AS receita_liquida,
    ROUND(SUM(COALESCE(d.valor_devolvido, 0)), 0)                    AS valor_devolvido,
    ROUND(100 * SUM(COALESCE(d.valor_devolvido, 0))
              / (SUM(a.receita) + SUM(COALESCE(d.valor_devolvido, 0))), 2) AS taxa_devolucao_pct
FROM curva_abc a
LEFT JOIN (
    SELECT codigo_produto, SUM(valor_devolvido) AS valor_devolvido
    FROM devolucoes_comuns
    GROUP BY codigo_produto
) d USING (codigo_produto)
GROUP BY a.classe
ORDER BY a.classe;

-- nome: Devoluções por mês
-- Valor devolvido no mês ÷ valor vendido no mesmo mês
WITH venda_mes AS (
    SELECT date_trunc('month', data) AS mes, SUM(receita) AS vendido
    FROM vendas
    GROUP BY mes
),
devolucao_mes AS (
    SELECT date_trunc('month', data) AS mes, SUM(valor_devolvido) AS devolvido
    FROM devolucoes_comuns
    GROUP BY mes
)
SELECT
    strftime(v.mes, '%Y-%m')                                    AS mes,
    ROUND(v.vendido, 0)                                         AS vendido,
    ROUND(COALESCE(d.devolvido, 0), 0)                          AS devolvido,
    ROUND(100 * COALESCE(d.devolvido, 0) / v.vendido, 2)        AS taxa_devolucao_pct
FROM venda_mes v
LEFT JOIN devolucao_mes d USING (mes)
WHERE v.mes < DATE '2011-12-01'
ORDER BY v.mes;
