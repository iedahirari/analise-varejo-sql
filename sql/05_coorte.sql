-- =============================================================================
-- 05 · Análise de coorte e retenção
-- Quantos clientes voltam a comprar depois do primeiro pedido?
-- Uma "coorte" é o grupo de clientes que fez a primeira compra no mesmo mês.
-- Para cada coorte, medimos que % ainda compra 1, 2, 3... meses depois.
-- Rodar: python rodar_sql.py sql/05_coorte.sql --csv
--
-- Dois cortes de período (explicados no README):
--   * dez/2009 fica fora das comparações: a base começa nesse mês, então ali
--     aparecem também clientes antigos, que não são novos de verdade;
--   * dez/2011 fica fora: tem só 9 dias de dados e faria a retenção despencar.
-- =============================================================================

-- nome: Cria a tabela coortes (uma linha por coorte e mês de vida)
CREATE OR REPLACE TABLE coortes AS
WITH
-- Passo 1: em que meses cada cliente comprou (um registro por cliente e mês)
atividade AS (
    SELECT DISTINCT
        id_cliente,
        date_trunc('month', data) AS mes
    FROM vendas
    WHERE id_cliente IS NOT NULL
      AND data < DATE '2011-12-01'
),

-- Passo 2: a coorte de cada cliente é o mês da primeira compra
primeira_compra AS (
    SELECT
        id_cliente,
        MIN(mes) AS coorte
    FROM atividade
    GROUP BY id_cliente
),

-- Passo 3: quantos meses depois da primeira compra cada atividade aconteceu
atividade_por_coorte AS (
    SELECT
        p.coorte,
        date_diff('month', p.coorte, a.mes) AS mes_de_vida,   -- 0 = mês da primeira compra
        a.id_cliente
    FROM atividade a
    JOIN primeira_compra p USING (id_cliente)
)

-- Passo 4: clientes ativos em cada mês de vida e % sobre o tamanho da coorte
SELECT
    coorte,
    mes_de_vida,
    COUNT(DISTINCT id_cliente)                                       AS clientes_ativos,
    FIRST_VALUE(COUNT(DISTINCT id_cliente))
        OVER (PARTITION BY coorte ORDER BY mes_de_vida)              AS tamanho_coorte,
    COUNT(DISTINCT id_cliente)
        / FIRST_VALUE(COUNT(DISTINCT id_cliente))
          OVER (PARTITION BY coorte ORDER BY mes_de_vida)            AS retencao
FROM atividade_por_coorte
GROUP BY coorte, mes_de_vida;

-- nome: Matriz de retenção das coortes de 2010 (% de clientes que voltaram)
-- Formato clássico: cada linha é uma coorte, cada coluna um mês de vida.
-- A "virada" de linhas para colunas é feita com agregação condicional (MAX + CASE),
-- que funciona em qualquer banco SQL.
SELECT
    strftime(coorte, '%Y-%m')                                               AS coorte,
    MAX(tamanho_coorte)                                                     AS clientes,
    ROUND(100 * MAX(CASE WHEN mes_de_vida = 1  THEN retencao END), 1)       AS m1,
    ROUND(100 * MAX(CASE WHEN mes_de_vida = 2  THEN retencao END), 1)       AS m2,
    ROUND(100 * MAX(CASE WHEN mes_de_vida = 3  THEN retencao END), 1)       AS m3,
    ROUND(100 * MAX(CASE WHEN mes_de_vida = 4  THEN retencao END), 1)       AS m4,
    ROUND(100 * MAX(CASE WHEN mes_de_vida = 5  THEN retencao END), 1)       AS m5,
    ROUND(100 * MAX(CASE WHEN mes_de_vida = 6  THEN retencao END), 1)       AS m6,
    ROUND(100 * MAX(CASE WHEN mes_de_vida = 9  THEN retencao END), 1)       AS m9,
    ROUND(100 * MAX(CASE WHEN mes_de_vida = 12 THEN retencao END), 1)       AS m12
FROM coortes
WHERE coorte BETWEEN DATE '2010-01-01' AND DATE '2010-12-01'
GROUP BY coorte
ORDER BY coorte;

-- nome: Curva média de retenção
-- Média ponderada pelo tamanho de cada coorte (coortes grandes pesam mais).
-- Cuidado: se ninguém de uma coorte comprou num mês, a tabela coortes não tem
-- essa linha. Por isso a grade coorte × mês é montada antes, e o que falta vira 0.
-- Só entram coortes que já tiveram tempo de chegar àquele mês de vida.
WITH
tamanhos AS (
    SELECT coorte, MAX(tamanho_coorte) AS tamanho
    FROM coortes
    WHERE coorte >= DATE '2010-01-01'
    GROUP BY coorte
),
meses AS (
    SELECT unnest([1, 2, 3, 6, 9, 12, 18]) AS mes_de_vida
),
grade AS (
    SELECT
        t.coorte,
        t.tamanho,
        m.mes_de_vida,
        COALESCE(c.clientes_ativos, 0) AS ativos
    FROM tamanhos t
    CROSS JOIN meses m
    LEFT JOIN coortes c
           ON c.coorte = t.coorte
          AND c.mes_de_vida = m.mes_de_vida
    -- a coorte precisa ter chegado a esse mês antes do fim dos dados (nov/2011)
    WHERE t.coorte + to_months(m.mes_de_vida) <= DATE '2011-11-01'
)
SELECT
    mes_de_vida,
    COUNT(*)                                            AS coortes_na_media,
    SUM(tamanho)                                        AS clientes_na_base,
    ROUND(100.0 * SUM(ativos) / SUM(tamanho), 1)        AS retencao_pct
FROM grade
GROUP BY mes_de_vida
ORDER BY mes_de_vida;

-- nome: Clientes que nunca voltaram
-- Entre os que estrearam de jan/2010 a mai/2011 (tiveram pelo menos 6 meses para voltar)
WITH por_cliente AS (
    SELECT
        id_cliente,
        MIN(date_trunc('month', data))           AS coorte,
        COUNT(DISTINCT date_trunc('month', data)) AS meses_com_compra
    FROM vendas
    WHERE id_cliente IS NOT NULL
      AND data < DATE '2011-12-01'
    GROUP BY id_cliente
)
SELECT
    COUNT(*)                                                        AS clientes,
    COUNT(*) FILTER (WHERE meses_com_compra = 1)                    AS compraram_so_no_primeiro_mes,
    ROUND(100.0 * COUNT(*) FILTER (WHERE meses_com_compra = 1) / COUNT(*), 1) AS pct_nunca_voltaram
FROM por_cliente
WHERE coorte BETWEEN DATE '2010-01-01' AND DATE '2011-05-01';
