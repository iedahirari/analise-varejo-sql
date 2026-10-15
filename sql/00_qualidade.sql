-- =============================================================================
-- 00 · Qualidade dos dados
-- Antes de qualquer análise: o que está faltando, repetido ou estranho na base?
-- Rodar: python rodar_sql.py sql/00_qualidade.sql
-- =============================================================================

-- nome: Tamanho e período da base
SELECT
    COUNT(*)                        AS linhas,
    COUNT(DISTINCT fatura)          AS faturas,
    COUNT(DISTINCT codigo_produto)  AS produtos,
    COUNT(DISTINCT id_cliente)      AS clientes,
    COUNT(DISTINCT pais)            AS paises,
    MIN(data_fatura)                AS primeira_venda,
    MAX(data_fatura)                AS ultima_venda
FROM vendas_brutas;

-- nome: Valores nulos por coluna
SELECT
    COUNT(*) - COUNT(fatura)          AS fatura_nula,
    COUNT(*) - COUNT(codigo_produto)  AS produto_nulo,
    COUNT(*) - COUNT(descricao)       AS descricao_nula,
    COUNT(*) - COUNT(quantidade)      AS quantidade_nula,
    COUNT(*) - COUNT(preco_unitario)  AS preco_nulo,
    COUNT(*) - COUNT(id_cliente)      AS cliente_nulo,
    ROUND(100.0 * (COUNT(*) - COUNT(id_cliente)) / COUNT(*), 1) AS pct_cliente_nulo
FROM vendas_brutas;

-- nome: Linhas exatamente repetidas
-- Mesma fatura, produto, quantidade, data e preço aparecendo mais de uma vez
SELECT
    SUM(vezes - 1) AS linhas_duplicadas,
    COUNT(*)       AS grupos_repetidos
FROM (
    SELECT COUNT(*) AS vezes
    FROM vendas_brutas
    GROUP BY fatura, codigo_produto, descricao, quantidade, data_fatura, preco_unitario, id_cliente, pais
    HAVING COUNT(*) > 1
);

-- nome: Tipos de fatura
-- Faturas que começam com "C" são cancelamentos (devoluções)
SELECT
    CASE
        WHEN fatura LIKE 'C%' THEN 'cancelamento (C...)'
        WHEN fatura LIKE 'A%' THEN 'ajuste contábil (A...)'
        ELSE 'venda'
    END AS tipo,
    COUNT(*)                                  AS linhas,
    SUM(CASE WHEN quantidade < 0 THEN 1 END)  AS quantidade_negativa,
    SUM(CASE WHEN preco_unitario <= 0 THEN 1 END) AS preco_zero_ou_negativo
FROM vendas_brutas
GROUP BY tipo
ORDER BY linhas DESC;

-- nome: Códigos que não são produtos
-- Frete, taxas, descontos e ajustes misturados com as vendas de mercadoria
SELECT
    codigo_produto,
    ANY_VALUE(descricao)          AS descricao,
    COUNT(*)                      AS linhas,
    ROUND(SUM(quantidade * preco_unitario), 2) AS valor_total
FROM vendas_brutas
WHERE NOT regexp_matches(codigo_produto, '^[0-9]{5}')
GROUP BY codigo_produto
ORDER BY linhas DESC
LIMIT 20;

-- nome: Vendas com preço zero
SELECT
    COUNT(*)                          AS linhas,
    COUNT(*) FILTER (WHERE id_cliente IS NULL) AS sem_cliente,
    ANY_VALUE(descricao)              AS exemplo_descricao
FROM vendas_brutas
WHERE preco_unitario = 0 AND fatura NOT LIKE 'C%';

-- nome: Países com mais linhas
SELECT pais, COUNT(*) AS linhas, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM vendas_brutas
GROUP BY pais
ORDER BY linhas DESC
LIMIT 8;
