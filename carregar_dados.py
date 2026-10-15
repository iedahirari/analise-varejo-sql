"""Baixa o dataset Online Retail II (UCI) e carrega no banco DuckDB data/varejo.duckdb.

Uso, na raiz do projeto:
    python carregar_dados.py

O resultado é a tabela `vendas_brutas`, exatamente como vem da planilha (as duas
abas juntas). A limpeza é feita depois, em SQL, no arquivo sql/01_limpeza.sql.
"""
import urllib.request
import zipfile
from pathlib import Path

import duckdb
import pandas as pd

URL = 'https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip'
PASTA = Path('data')
ZIP = PASTA / 'bruto' / 'online_retail_ii.zip'
PLANILHA = PASTA / 'bruto' / 'online_retail_II.xlsx'
BANCO = PASTA / 'varejo.duckdb'


def baixar():
    if PLANILHA.exists():
        print(f'Planilha já existe: {PLANILHA}')
        return
    ZIP.parent.mkdir(parents=True, exist_ok=True)
    print(f'Baixando {URL} (cerca de 45 MB)...')
    urllib.request.urlretrieve(URL, ZIP)
    with zipfile.ZipFile(ZIP) as z:
        z.extract('online_retail_II.xlsx', ZIP.parent)


def carregar():
    # A planilha tem uma aba por período (2009-2010 e 2010-2011)
    print('Lendo a planilha (leva cerca de 1 minuto)...')
    abas = pd.read_excel(PLANILHA, sheet_name=None, dtype={'Invoice': str, 'StockCode': str, 'Customer ID': 'Int64'})
    vendas = pd.concat(abas.values(), ignore_index=True)
    vendas.columns = ['fatura', 'codigo_produto', 'descricao', 'quantidade', 'data_fatura', 'preco_unitario', 'id_cliente', 'pais']

    with duckdb.connect(str(BANCO)) as banco:
        banco.execute('CREATE OR REPLACE TABLE vendas_brutas AS SELECT * FROM vendas')
        linhas = banco.execute('SELECT COUNT(*) FROM vendas_brutas').fetchone()[0]
    print(f'Tabela vendas_brutas criada com {linhas:,} linhas em {BANCO}')


if __name__ == '__main__':
    baixar()
    carregar()
