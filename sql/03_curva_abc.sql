-- =============================================================================
-- 03 · Curva ABC de produtos
-- Quais produtos sustentam a receita? A curva ABC ordena os produtos do que mais
-- vende para o que menos vende e acumula a participação na receita:
--   A -> produtos que, juntos, somam os primeiros 80% da receita
--   B -> os próximos 15% (até 95%)
--   C -> os últimos 5%
-- Técnica principal: SUM() OVER (ORDER BY ...) para o acumulado (função de janela).
-- A receita é LÍQUIDA (vendas menos devoluções): dois pedidos gigantes foram
-- cancelados inteiros e, sem descontar, colocariam produtos falsos no top 10.
-- Rodar: python rodar_sql.py sql/03_curva_abc.sql --csv
-- =============================================================================

-- nome: Classificação ABC por produto
CREATE OR REPLACE TABLE curva_abc AS
WITH vendido AS (
    SELECT
        codigo_produto,
        SUM(receita)            AS receita_bruta,
        SUM(quantidade)         AS unidades,
        COUNT(DISTINCT fatura)  AS pedidos
    FROM vendas
    GROUP BY codigo_produto
),
devolvido AS (
    SELECT codigo_produto, SUM(valor_devolvido) AS valor_devolvido
    FROM devolucoes
    GROUP BY codigo_produto
),
por_produto AS (
    SELECT
        v.codigo_produto,
        v.receita_bruta - COALESCE(d.valor_devolvido, 0)   AS receita,   -- receita líquida
        v.unidades,
        v.pedidos
    FROM vendido v
    LEFT JOIN devolvido d USING (codigo_produto)
    -- produtos com receita líquida zero ou negativa (tudo devolvido) ficam fora da curva
    WHERE v.receita_bruta - COALESCE(d.valor_devolvido, 0) > 0
),
acumulado AS (
    SELECT
        *,
        receita / SUM(receita) OVER ()                                    AS participacao,
        SUM(receita) OVER (ORDER BY receita DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            / SUM(receita) OVER ()                                        AS participacao_acumulada,
        ROW_NUMBER() OVER (ORDER BY receita DESC)                         AS ranking
    FROM por_produto
)
SELECT
    *,
    CASE
        -- o produto entra na classe em que a receita acumulada ANTES dele estava
        WHEN participacao_acumulada - participacao < 0.80 THEN 'A'
        WHEN participacao_acumulada - participacao < 0.95 THEN 'B'
        ELSE 'C'
    END AS classe
FROM acumulado;

-- nome: Resumo por classe
SELECT
    classe,
    COUNT(*)                                                    AS produtos,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_produtos,
    ROUND(SUM(receita), 0)                                      AS receita,
    ROUND(100.0 * SUM(receita) / SUM(SUM(receita)) OVER (), 1)  AS pct_receita
FROM curva_abc
GROUP BY classe
ORDER BY classe;

-- nome: Top 15 produtos
SELECT
    c.ranking,
    c.codigo_produto,
    p.descricao,
    ROUND(c.receita, 0)                         AS receita,
    ROUND(100 * c.participacao, 2)              AS pct_receita,
    ROUND(100 * c.participacao_acumulada, 1)    AS pct_acumulado,
    c.classe
FROM curva_abc c
LEFT JOIN produtos p USING (codigo_produto)
ORDER BY c.ranking
LIMIT 15;

-- nome: Produtos classe C que ainda ocupam espaço
-- Muitos itens de baixa venda: candidatos a sair do catálogo ou a promoção
SELECT
    COUNT(*)                                    AS produtos_c,
    COUNT(*) FILTER (WHERE pedidos <= 5)        AS vendidos_ate_5_vezes,
    ROUND(SUM(receita), 0)                      AS receita_total_c
FROM curva_abc
WHERE classe = 'C';
