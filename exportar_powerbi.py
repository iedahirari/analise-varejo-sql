"""Exporta as tabelas tratadas do DuckDB para o Power BI, em modelo estrela.

Uso, na raiz do projeto (depois de rodar os arquivos sql/01 a sql/06):
    python exportar_powerbi.py          -> arquivos .parquet (recomendado)
    python exportar_powerbi.py --csv    -> arquivos .csv

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


def main():
    formato = 'csv' if '--csv' in sys.argv else 'parquet'
    SAIDA.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(str(BANCO), read_only=True) as banco:
        for nome, sql in CONSULTAS.items():
            destino = SAIDA / f'{nome}.{formato}'
            opcoes = "(FORMAT parquet)" if formato == 'parquet' else "(FORMAT csv, HEADER)"
            banco.execute(f"COPY ({sql}) TO '{destino.as_posix()}' {opcoes}")
            linhas = banco.execute(f'SELECT COUNT(*) FROM ({sql})').fetchone()[0]
            print(f'{destino}  ({linhas:,} linhas)')


if __name__ == '__main__':
    main()
