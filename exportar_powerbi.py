"""Exporta as tabelas tratadas do DuckDB para o Power BI, em modelo estrela.

Uso, na raiz do projeto (depois de rodar os arquivos sql/01 a sql/06):
    python exportar_powerbi.py          -> arquivos .parquet (recomendado)
    python exportar_powerbi.py --csv    -> arquivos .csv
    python exportar_powerbi.py --web    -> CSVs pequenos e agregados para o Power BI na web (data/powerbi_web/)

Saída em data/powerbi/:
    fato_vendas       uma linha por item vendido
    fato_devolucoes   uma linha por item devolvido
    dim_produto       produto, descrição e classe ABC
    dim_cliente       cliente, segmento RFM, notas e coorte
    coortes           retenção por coorte e mês de vida (para a matriz de calor)

Por que Parquet: o Power BI lê os tipos certos (data, número, texto) direto do
arquivo. Com CSV, o Power BI em português pode confundir o ponto decimal.
"""
import sys
from pathlib import Path

import duckdb

BANCO = Path('data') / 'varejo.duckdb'
SAIDA = Path('data') / 'powerbi'

CONSULTAS = {
    'fato_vendas': """
        SELECT fatura, codigo_produto, id_cliente, data, quantidade, preco_unitario, receita, pais
        FROM vendas
    """,
    'fato_devolucoes': """
        SELECT
            fatura, codigo_produto, id_cliente, data, quantidade_devolvida, valor_devolvido, pais,
            valor_devolvido >= 50000 AS cancelamento_gigante
        FROM devolucoes
    """,
    'dim_produto': """
        SELECT
            p.codigo_produto,
            p.descricao,
            COALESCE(a.classe, 'Sem receita líquida')   AS classe_abc,
            a.ranking                                   AS ranking_abc,
            a.participacao_acumulada                    AS participacao_acumulada
        FROM produtos p
        LEFT JOIN curva_abc a USING (codigo_produto)
    """,
    'dim_cliente': """
        SELECT
            id_cliente, pais, segmento, codigo_rfm, nota_r, nota_f, nota_m,
            recencia_dias, frequencia, monetario AS gasto_liquido,
            primeira_compra, ultima_compra,
            CAST(date_trunc('month', primeira_compra) AS DATE) AS coorte
        FROM rfm
        UNION ALL
        -- clientes que só aparecem em devoluções (compraram antes de dez/2009);
        -- sem eles, o Power BI mostraria "(Em branco)" nos gráficos de devolução
        SELECT DISTINCT
            id_cliente, pais, 'Sem compra no período', NULL, NULL, NULL, NULL,
            NULL, 0, 0, NULL, NULL, NULL
        FROM devolucoes
        WHERE id_cliente IS NOT NULL
          AND id_cliente NOT IN (SELECT id_cliente FROM rfm)
    """,
    'coortes': """
        SELECT CAST(coorte AS DATE) AS coorte, mes_de_vida, clientes_ativos, tamanho_coorte, retencao
        FROM coortes
        WHERE coorte >= DATE '2010-01-01'
    """,
}

# Versão para o Power BI na web (app.powerbi.com), que só aceita CSV e Excel.
# Tabelas pequenas e já agregadas, uma por página do relatório: assim nenhum
# arquivo passa de alguns milhares de linhas e as contagens distintas (pedidos,
# clientes) já chegam certas, sem depender de medidas DAX.
CONSULTAS_WEB = {
    'indicadores': """
        SELECT
            ROUND((SELECT SUM(receita) FROM vendas), 2)                         AS receita_bruta,
            ROUND((SELECT SUM(valor_devolvido) FROM devolucoes), 2)             AS valor_devolvido,
            ROUND((SELECT SUM(receita) FROM vendas)
                - (SELECT SUM(valor_devolvido) FROM devolucoes), 2)            AS receita_liquida,
            (SELECT COUNT(DISTINCT fatura) FROM vendas)                         AS pedidos,
            (SELECT COUNT(DISTINCT id_cliente) FROM vendas)                     AS clientes,
            ROUND((SELECT SUM(receita) / COUNT(DISTINCT fatura) FROM vendas), 2) AS ticket_medio,
            ROUND((SELECT SUM(valor_devolvido) FROM devolucoes)
                / (SELECT SUM(receita) FROM vendas), 4)                         AS taxa_devolucao,
            ROUND((SELECT SUM(valor_devolvido) FROM devolucoes WHERE valor_devolvido < 50000)
                / (SELECT SUM(receita) FROM vendas), 4)                         AS taxa_devolucao_sem_gigantes
    """,
    'vendas_diarias': """
        SELECT
            data,
            strftime(data, '%Y-%m')         AS ano_mes,
            year(data)                      AS ano,
            ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'][isodow(data)] AS dia_semana,
            isodow(data)                    AS dia_semana_num,
            pais,
            ROUND(SUM(receita), 2)          AS receita,
            COUNT(DISTINCT fatura)          AS pedidos,
            CAST(SUM(quantidade) AS BIGINT) AS unidades
        FROM vendas
        WHERE data < DATE '2011-12-01'
        GROUP BY ALL
        ORDER BY data, pais
    """,
    'produtos': """
        SELECT
            a.ranking,
            a.codigo_produto,
            p.descricao,
            a.classe                                        AS classe_abc,
            ROUND(a.receita, 2)                             AS receita_liquida,
            CAST(a.unidades AS BIGINT)                      AS unidades,
            a.pedidos,
            ROUND(a.participacao_acumulada, 4)              AS participacao_acumulada,
            ROUND(COALESCE(d.valor_devolvido, 0), 2)        AS valor_devolvido,
            COALESCE(d.devolucoes, 0)                       AS vezes_devolvido
        FROM curva_abc a
        LEFT JOIN produtos p USING (codigo_produto)
        LEFT JOIN (
            SELECT codigo_produto, SUM(valor_devolvido) AS valor_devolvido, COUNT(DISTINCT fatura) AS devolucoes
            FROM devolucoes
            WHERE valor_devolvido < 50000
            GROUP BY codigo_produto
        ) d USING (codigo_produto)
        ORDER BY a.ranking
    """,
    'clientes_rfm': """
        SELECT id_cliente, pais, segmento, codigo_rfm, recencia_dias, frequencia,
               ROUND(monetario, 2) AS gasto_liquido, ultima_compra
        FROM rfm
    """,
    'coortes': """
        SELECT strftime(coorte, '%Y-%m') AS coorte, mes_de_vida, clientes_ativos, tamanho_coorte,
               ROUND(retencao, 4) AS retencao
        FROM coortes
        WHERE coorte >= DATE '2010-01-01' AND mes_de_vida BETWEEN 1 AND 12
    """,
    'devolucoes_mensais': """
        WITH v AS (SELECT date_trunc('month', data) AS mes, SUM(receita) AS vendido FROM vendas GROUP BY 1),
             d AS (SELECT date_trunc('month', data) AS mes,
                          SUM(valor_devolvido) AS devolvido,
                          SUM(valor_devolvido) FILTER (WHERE valor_devolvido < 50000) AS devolvido_sem_gigantes
                   FROM devolucoes GROUP BY 1)
        SELECT strftime(v.mes, '%Y-%m') AS ano_mes,
               ROUND(v.vendido, 2) AS vendido,
               ROUND(COALESCE(d.devolvido, 0), 2) AS devolvido,
               ROUND(COALESCE(d.devolvido_sem_gigantes, 0), 2) AS devolvido_sem_gigantes,
               ROUND(COALESCE(d.devolvido_sem_gigantes, 0) / v.vendido, 4) AS taxa_devolucao
        FROM v LEFT JOIN d USING (mes)
        WHERE v.mes < DATE '2011-12-01'
        ORDER BY ano_mes
    """,
}


def main():
    web = '--web' in sys.argv
    formato = 'csv' if ('--csv' in sys.argv or web) else 'parquet'
    consultas = CONSULTAS_WEB if web else CONSULTAS
    saida = Path('data') / 'powerbi_web' if web else SAIDA
    saida.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(str(BANCO), read_only=True) as banco:
        for nome, sql in consultas.items():
            destino = saida / f'{nome}.{formato}'
            if web:
                # Padrão brasileiro: o Power BI em português lê "196.1" como 1961.
                # Com ponto e vírgula separando colunas, a vírgula pode ser o decimal.
                # (o DuckDB não grava CSV com vírgula decimal, por isso o pandas)
                banco.sql(sql).df().to_csv(destino, sep=';', decimal=',', index=False, encoding='utf-8')
            else:
                opcoes = "(FORMAT parquet)" if formato == 'parquet' else "(FORMAT csv, HEADER)"
                banco.execute(f"COPY ({sql}) TO '{destino.as_posix()}' {opcoes}")
            linhas = banco.execute(f'SELECT COUNT(*) FROM ({sql})').fetchone()[0]
            print(f'{destino}  ({linhas:,} linhas)')


if __name__ == '__main__':
    main()
