-- =============================================================================
-- 04 · Segmentação RFM de clientes
-- Quem são os melhores clientes e quem está deixando de comprar?
--   R (Recência)   -> há quantos dias o cliente comprou pela última vez
--   F (Frequência) -> quantos pedidos ele fez
--   M (Monetário)  -> quanto ele gastou, descontando o que devolveu
-- Cada métrica vira uma nota de 1 a 5 (5 = melhor) e a combinação define o segmento.
-- Rodar: python rodar_sql.py sql/04_rfm.sql --csv
-- =============================================================================

-- nome: Cria a tabela rfm (uma linha por cliente)
CREATE OR REPLACE TABLE rfm AS
WITH
-- Data de referência: o dia seguinte à última venda da base (10/12/2011).
-- Usar a data de hoje faria todos os clientes parecerem inativos há anos.
referencia AS (
    SELECT MAX(data) + 1 AS data_ref          -- DATE + 1 = dia seguinte (continua DATE)
    FROM vendas
),

-- Quanto cada cliente devolveu. Sem isso, quem compra e cancela no mesmo dia
-- (ex.: cliente 12346, que devolveu £ 77 mil de £ 77 mil) pareceria um grande cliente.
devolvido AS (
    SELECT id_cliente, SUM(valor_devolvido) AS valor_devolvido
    FROM devolucoes
    WHERE id_cliente IS NOT NULL
    GROUP BY id_cliente
),

-- Passo 1: as três métricas de cada cliente identificado
metricas AS (
    SELECT
        v.id_cliente,
        ANY_VALUE(v.pais)                               AS pais,
        MIN(v.data)                                     AS primeira_compra,
        MAX(v.data)                                     AS ultima_compra,
        date_diff('day', MAX(v.data), r.data_ref)       AS recencia_dias,
        COUNT(DISTINCT v.fatura)                        AS frequencia,
        SUM(v.receita)                                  AS gasto_bruto,
        COALESCE(ANY_VALUE(d.valor_devolvido), 0)       AS valor_devolvido,
        SUM(v.receita) - COALESCE(ANY_VALUE(d.valor_devolvido), 0) AS monetario   -- gasto líquido
    FROM vendas v
    CROSS JOIN referencia r
    LEFT JOIN devolvido d ON d.id_cliente = v.id_cliente
    WHERE v.id_cliente IS NOT NULL
    GROUP BY v.id_cliente, r.data_ref
),

-- Passo 2: notas de 1 a 5
notas AS (
    SELECT
        *,
        -- Recência e valor: quintis (cada nota fica com ~20% dos clientes).
        -- Recência é "quanto menor, melhor", por isso ordena do maior para o menor.
        NTILE(5) OVER (ORDER BY recencia_dias DESC)     AS nota_r,
        NTILE(5) OVER (ORDER BY monetario ASC)          AS nota_m,
        -- Frequência: faixas fixas. 28% dos clientes compraram uma única vez;
        -- com NTILE, clientes empatados cairiam em notas diferentes por acaso.
        CASE
            WHEN frequencia >= 10 THEN 5
            WHEN frequencia >= 5  THEN 4
            WHEN frequencia >= 3  THEN 3
            WHEN frequencia = 2   THEN 2
            ELSE 1
        END                                             AS nota_f
    FROM metricas
)

-- Passo 3: segmento a partir das notas (a ordem dos WHEN importa:
-- o primeiro que for verdadeiro define o segmento)
SELECT
    *,
    CAST(nota_r AS VARCHAR) || nota_f || nota_m         AS codigo_rfm,
    CASE
        WHEN nota_r >= 4 AND nota_f >= 4 THEN 'Campeões'
        WHEN nota_r >= 3 AND nota_f >= 3 THEN 'Fiéis'
        WHEN nota_r >= 4                 THEN 'Novos ou promissores'
        WHEN nota_r <= 2 AND nota_f >= 3 THEN 'Em risco'
        WHEN nota_r <= 2                 THEN 'Perdidos'
        ELSE                                  'Precisam de atenção'
    END                                                 AS segmento
FROM notas;

-- nome: Resumo por segmento
SELECT
    segmento,
    COUNT(*)                                                        AS clientes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)              AS pct_clientes,
    ROUND(SUM(monetario), 0)                                        AS receita,
    ROUND(100.0 * SUM(monetario) / SUM(SUM(monetario)) OVER (), 1)  AS pct_receita,
    ROUND(MEDIAN(recencia_dias), 0)                                 AS recencia_mediana_dias,
    ROUND(MEDIAN(frequencia), 0)                                    AS pedidos_mediana,
    ROUND(MEDIAN(monetario), 0)                                     AS gasto_mediano
FROM rfm
GROUP BY segmento
ORDER BY receita DESC;

-- nome: Conferência das notas
-- Cada nota de R e M deve ter ~20% dos clientes; F segue as faixas fixas
SELECT
    nota,
    COUNT(*) FILTER (WHERE nota_r = nota)   AS clientes_nota_r,
    COUNT(*) FILTER (WHERE nota_f = nota)   AS clientes_nota_f,
    COUNT(*) FILTER (WHERE nota_m = nota)   AS clientes_nota_m
FROM rfm, range(1, 6) AS t(nota)
GROUP BY nota
ORDER BY nota;

-- nome: Clientes em risco de maior valor
-- Lista de ação: compravam muito e pararam. Prioridade para contato e oferta.
SELECT
    id_cliente,
    pais,
    ultima_compra,
    recencia_dias,
    frequencia,
    ROUND(monetario, 0)     AS gasto_liquido,
    codigo_rfm
FROM rfm
WHERE segmento = 'Em risco'
ORDER BY monetario DESC
LIMIT 10;
