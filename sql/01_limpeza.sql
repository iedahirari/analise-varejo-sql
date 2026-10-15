-- =============================================================================
-- 01 · Limpeza e modelagem
-- Transforma a tabela bruta em três tabelas prontas para análise:
--   vendas     -> uma linha por item vendido (só mercadoria, sem duplicadas)
--   devolucoes -> itens cancelados (faturas que começam com "C")
--   produtos   -> um nome por código de produto
-- Rodar: python rodar_sql.py sql/01_limpeza.sql
-- =============================================================================

-- nome: Cria a tabela de vendas
-- Regras (vindas do diagnóstico em 00_qualidade.sql):
--   1. remove 34 mil linhas repetidas (DISTINCT);
--   2. remove cancelamentos (C...) e ajustes contábeis (A...);
--   3. remove quantidade ou preço zero/negativo (brindes, correções de estoque);
--   4. mantém só códigos de mercadoria (5 dígitos), tirando frete, taxas e descontos.
-- Vendas sem cliente identificado ficam, porque contam no faturamento;
-- as análises de clientes (RFM e coorte) filtram id_cliente depois.
CREATE OR REPLACE TABLE vendas AS
SELECT DISTINCT
    fatura,
    upper(codigo_produto)                 AS codigo_produto,
    quantidade,
    preco_unitario,
    quantidade * preco_unitario           AS receita,
    data_fatura,
    CAST(data_fatura AS DATE)             AS data,
    id_cliente,
    pais
FROM vendas_brutas
WHERE fatura NOT LIKE 'C%'
  AND fatura NOT LIKE 'A%'
  AND quantidade > 0
  AND preco_unitario > 0
  AND regexp_matches(codigo_produto, '^[0-9]{5}');

-- nome: Cria a tabela de devoluções
CREATE OR REPLACE TABLE devolucoes AS
SELECT DISTINCT
    fatura,
    upper(codigo_produto)                 AS codigo_produto,
    -quantidade                           AS quantidade_devolvida,
    -quantidade * preco_unitario          AS valor_devolvido,
    CAST(data_fatura AS DATE)             AS data,
    id_cliente,
    pais
FROM vendas_brutas
WHERE fatura LIKE 'C%'
  AND regexp_matches(codigo_produto, '^[0-9]{5}');

-- nome: Cria a tabela de produtos
-- O mesmo código às vezes aparece com descrições diferentes (erros de digitação);
-- fica a descrição mais usada para cada código.
CREATE OR REPLACE TABLE produtos AS
SELECT
    upper(codigo_produto)                 AS codigo_produto,
    mode(trim(descricao))                 AS descricao
FROM vendas_brutas
WHERE descricao IS NOT NULL
  AND regexp_matches(codigo_produto, '^[0-9]{5}')
GROUP BY 1;

-- nome: Conferência: quanto sobrou depois da limpeza
SELECT
    (SELECT COUNT(*) FROM vendas_brutas)                         AS linhas_brutas,
    (SELECT COUNT(*) FROM vendas)                                AS linhas_vendas,
    ROUND(100.0 * (SELECT COUNT(*) FROM vendas) / (SELECT COUNT(*) FROM vendas_brutas), 1) AS pct_mantido,
    (SELECT COUNT(*) FROM devolucoes)                            AS linhas_devolucoes,
    (SELECT COUNT(*) FROM produtos)                              AS produtos,
    (SELECT COUNT(DISTINCT id_cliente) FROM vendas)              AS clientes;
