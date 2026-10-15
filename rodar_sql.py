"""Executa um arquivo .sql no banco data/varejo.duckdb e mostra o resultado de cada consulta.

Uso, na raiz do projeto:
    python rodar_sql.py sql/02_visao_geral.sql
    python rodar_sql.py sql/03_curva_abc.sql --csv     (também salva cada resultado em resultados/)

Cada consulta do arquivo deve começar com um comentário `-- nome: ...`, que vira o
título do resultado e o nome do CSV.
"""
import re
import sys
import unicodedata
from pathlib import Path

import duckdb

BANCO = Path('data') / 'varejo.duckdb'


def nome_arquivo(texto):
    """'Receita por mês' -> 'receita_por_mes'"""
    sem_acento = unicodedata.normalize('NFKD', texto).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', '_', sem_acento.lower()).strip('_')


def consultas(texto):
    """Separa o arquivo em blocos, um por `-- nome:`."""
    blocos = re.split(r'^-- nome:\s*', texto, flags=re.M)
    for bloco in blocos[1:]:
        nome, _, sql = bloco.partition('\n')
        yield nome.strip(), sql.strip().rstrip(';')


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    arquivo = Path(sys.argv[1])
    salvar_csv = '--csv' in sys.argv

    with duckdb.connect(str(BANCO)) as banco:
        for nome, sql in consultas(arquivo.read_text(encoding='utf-8')):
            print(f'\n=== {nome} ===')
            resultado = banco.sql(sql)
            if resultado is None:  # CREATE, DROP etc. não devolvem linhas
                print('ok')
                continue
            resultado.show(max_rows=25, max_width=160)
            if salvar_csv:
                destino = Path('resultados') / f'{arquivo.stem}__{nome_arquivo(nome)}.csv'
                destino.parent.mkdir(exist_ok=True)
                resultado.write_csv(str(destino))


if __name__ == '__main__':
    main()
