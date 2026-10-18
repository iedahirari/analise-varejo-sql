# Guia do dashboard no Power BI

Passo a passo para montar o dashboard a partir das tabelas exportadas pelo SQL. Ao final, salve o arquivo como `powerbi/dashboard_varejo.pbix`.

Há dois caminhos:

- **Power BI Desktop** (Windows): modelo estrela completo, com medidas DAX. Seções 1 a 8.
- **Power BI na web** (app.powerbi.com, qualquer sistema): tabelas já agregadas pelo SQL, sem DAX. Seção 0, logo abaixo. **O dashboard publicado do projeto foi feito por este caminho.**

## 0. Caminho web (app.powerbi.com)

A versão web só aceita CSV e Excel, então o script gera tabelas pequenas e já calculadas:

```bash
python exportar_powerbi.py --web
```

Os arquivos ficam em `data/powerbi_web/`, separados por **ponto e vírgula** e com **vírgula decimal** (padrão brasileiro):

| Arquivo | Conteúdo | Visual |
| --- | --- | --- |
| `indicadores.csv` | 1 linha com os totais (receita, pedidos, clientes, ticket, taxa de devolução) | Cartões |
| `vendas_diarias.csv` | receita, pedidos e unidades por dia e país, até nov/2011 | Linha mensal e dia da semana |
| `clientes_rfm.csv` | 1 linha por cliente com segmento e gasto líquido | Barras por segmento |
| `coortes.csv` | retenção por coorte e mês de vida (1 a 12) | Matriz de calor |
| `produtos.csv` | curva ABC e valor devolvido por produto (sem os 2 cancelamentos gigantes) | Top 10 devoluções |
| `devolucoes_mensais.csv` | taxa de devolução por mês | (reserva para uma 2ª página) |

### Importar

1. **Meu workspace → Novo item → Modelo semântico → Obter dados → Arquivo de texto/CSV**, envie os 6 arquivos de uma vez.
2. Antes de criar o modelo, confira no Power Query se os números decimais vieram certos (ex.: `497,07`, não `49707`).

> ⚠️ **Armadilha do separador decimal.** A interface em português lê vírgula como decimal, mas a **atualização no serviço** pode usar a cultura `en-US` e ler `18925714,33` como dezoito bilhões. A correção é fixar a cultura no passo de tipos de cada tabela. Na **exibição TMDL** do modelo (ou no Power Query), troque o final do passo `Table.TransformColumnTypes(...)` de `}})` para `}}, "pt-BR")`. Depois, **Atualizar agora**.

Para conferir sem montar visual, use a **exibição de consulta DAX** do modelo:

```dax
EVALUATE
ROW (
    "receita_liquida", SUM ( indicadores[receita_liquida] ),
    "ticket", SUM ( indicadores[ticket_medio] ),
    "taxa", SUM ( indicadores[taxa_devolucao] ),
    "vendas_diarias", SUM ( vendas_diarias[receita] )
)
```

Deve retornar 18.925.714,33 · 497,07 · 0,0365 · 19.027.652,67 (vendas até nov/2011).

### Página executiva (1920 × 1080)

| Visual | Campos | Ajustes |
| --- | --- | --- |
| Cartão (novo), topo | `indicadores`: receita_liquida, pedidos, clientes, ticket_medio, taxa_devolucao | Renomeie cada campo (clique duplo em **Valor**). Pedidos e clientes com **Exibir unidades = Nenhum**; taxa em porcentagem com 2 casas |
| Linha | eixo `vendas_diarias[ano_mes]`, valor `receita` | **⋯ → Classificar por → ano_mes → ordem crescente** (o padrão ordena pelo valor e embaralha os meses) |
| Colunas | eixo `vendas_diarias[dia_semana]`, valor `pedidos` | |
| Barras | eixo `clientes_rfm[segmento]`, valor `gasto_liquido` | Rótulos de dados com 2 casas |
| Matriz | linhas `coortes[coorte]` (sem hierarquia de datas, formato `yyyy-MM`), colunas `mes_de_vida`, valores `retencao` (**Máximo**, porcentagem) | Subtotais desligados; **Formatação condicional → Cor da tela de fundo** (branco → azul) |
| Tabela | `produtos[descricao]`, `valor_devolvido`, `vezes_devolvido` | Filtro do visual **N superior = 10 por valor_devolvido**; clique no cabeçalho para ordenar |

Use títulos que dizem a conclusão: "Receita mensal: pico de Natal em novembro", "Campeões geram 70% da receita", "Retenção por coorte: só 1 em cada 5 clientes novos volta no mês seguinte".

**Dicas da versão web:**

- Para tamanho e posição exatos, use **Formatar visual → Geral → Propriedades** em vez de arrastar.
- Clicar numa barra ou linha de tabela **filtra os outros visuais**. Antes de salvar ou tirar print, clique de novo nela para limpar a seleção.
- O formato `mmm/yyyy` aparece como `000/2010` na versão web em português. Use `yyyy-MM`.

## 1. Gerar os dados

Na raiz do projeto (depois de rodar `sql/01` a `sql/06`):

```bash
python exportar_powerbi.py
```

Os arquivos ficam em `data/powerbi/`, no formato **Parquet**, que já guarda os tipos de cada coluna (data, número, texto). Assim o Power BI em português não confunde o ponto decimal, que é um problema comum com CSV.

## 2. Importar no Power BI

1. **Página Inicial → Obter dados → Mais... → Parquet → Conectar.**
2. Escolha `data/powerbi/fato_vendas.parquet` e clique em **Carregar**.
3. Repita para `fato_devolucoes`, `dim_produto`, `dim_cliente` e `coortes`.

## 3. Tabela de calendário (DAX)

**Modelagem → Nova tabela**, cole:

```dax
dCalendario =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2009, 12, 1 ), DATE ( 2011, 12, 31 ) ),
    "Ano", YEAR ( [Date] ),
    "Mes Num", MONTH ( [Date] ),
    "Ano-Mes", FORMAT ( [Date], "yyyy-mm" ),
    "Mes", FORMAT ( [Date], "mmm/yy" ),
    "Dia da Semana", FORMAT ( [Date], "dddd" ),
    "Dia da Semana Num", WEEKDAY ( [Date], 2 )
)
```

Depois:

- Clique na tabela `dCalendario` → **Ferramentas da tabela → Marcar como tabela de datas** → coluna `Date`. Sem isso, as funções de comparação com o ano anterior não funcionam.
- Selecione a coluna **`Mes`** → **Ferramentas de coluna → Classificar por coluna → `Ano-Mes`**.
- Selecione **`Dia da Semana`** → **Classificar por coluna → `Dia da Semana Num`**.

> ⚠️ **Este é o passo que evita o erro do dashboard da Olist:** sem classificar o mês pela coluna `Ano-Mes`, o Power BI ordena os meses pelo valor ou em ordem alfabética, e a linha do tempo fica embaralhada.

## 4. Relacionamentos (modelo estrela)

Na **Exibição de modelo**, arraste para criar (todos **muitos para um**, com filtro em direção única):

| De (muitos) | Para (um) |
| --- | --- |
| `fato_vendas[codigo_produto]` | `dim_produto[codigo_produto]` |
| `fato_vendas[id_cliente]` | `dim_cliente[id_cliente]` |
| `fato_vendas[data]` | `dCalendario[Date]` |
| `fato_devolucoes[codigo_produto]` | `dim_produto[codigo_produto]` |
| `fato_devolucoes[id_cliente]` | `dim_cliente[id_cliente]` |
| `fato_devolucoes[data]` | `dCalendario[Date]` |

A tabela `coortes` fica **sem relacionamento**: ela já vem calculada do SQL e só alimenta a matriz de retenção.

## 5. Medidas (DAX)

Crie uma tabela vazia para organizar (**Página Inicial → Inserir dados** → nome `_Medidas` → Carregar). Depois, com ela selecionada, **Nova medida** para cada uma:

```dax
Receita Bruta = SUM ( fato_vendas[receita] )
```

```dax
Valor Devolvido = SUM ( fato_devolucoes[valor_devolvido] )
```

```dax
Receita Líquida = [Receita Bruta] - [Valor Devolvido]
```

```dax
Pedidos = DISTINCTCOUNT ( fato_vendas[fatura] )
```

```dax
Ticket Médio = DIVIDE ( [Receita Bruta], [Pedidos] )
```

```dax
Clientes = DISTINCTCOUNTNOBLANK ( fato_vendas[id_cliente] )
```

```dax
Taxa de Devolução = DIVIDE ( [Valor Devolvido], [Receita Bruta] )
```

```dax
Taxa de Devolução sem Gigantes =
DIVIDE (
    CALCULATE ( [Valor Devolvido], fato_devolucoes[cancelamento_gigante] = FALSE () ),
    [Receita Bruta]
)
```

```dax
Receita Ano Anterior = CALCULATE ( [Receita Bruta], SAMEPERIODLASTYEAR ( dCalendario[Date] ) )
```

```dax
Crescimento vs Ano Anterior = DIVIDE ( [Receita Bruta] - [Receita Ano Anterior], [Receita Ano Anterior] )
```

```dax
% da Receita Líquida = DIVIDE ( [Receita Líquida], CALCULATE ( [Receita Líquida], ALL ( dim_produto ) ) )
```

**Formatação:** `Receita...`, `Valor Devolvido` e `Ticket Médio` como **Moeda** (símbolo £, 0 casas decimais). As taxas, o `Crescimento` e o `% da Receita` como **Porcentagem** (1 casa decimal).

**Por que medidas e não colunas calculadas?** As medidas são calculadas na hora, respeitando os filtros do visual (ano, país, segmento...). `DISTINCTCOUNT` e `DIVIDE` não funcionariam como coluna.

## 6. Páginas do dashboard

Use as mesmas 3–4 cores em todas as páginas e deixe um título que **diz a conclusão**, não só o assunto (ex.: "24% dos clientes geram 70% da receita" em vez de "Clientes por segmento").

### Página 1 · Visão geral
- **5 cartões:** Receita Líquida, Pedidos, Ticket Médio, Clientes, Taxa de Devolução.
- **Gráfico de linhas:** eixo X = `dCalendario[Mes]`, valores = `Receita Bruta` e `Receita Ano Anterior`. Filtre o visual em `dCalendario[Date]` **antes de 01/12/2011**, porque dezembro de 2011 tem só 9 dias.
- **Colunas:** eixo = `dCalendario[Dia da Semana]`, valor = `Pedidos`. Vai aparecer o sábado quase vazio.
- **Barras horizontais:** `fato_vendas[pais]` × `Receita Bruta`, com o filtro do visual em **N superior = 10**.
- **Segmentação de dados:** `dCalendario[Ano]`.

### Página 2 · Produtos (curva ABC)
- **Gráfico de colunas e linhas (Pareto):** eixo X = `dim_produto[descricao]`, colunas = `Receita Líquida`, linha = `dim_produto[participacao_acumulada]` (agregação **Máximo**). Filtre `dim_produto[ranking_abc]` **menor ou igual a 50** e classifique pelo `ranking_abc` em ordem crescente.
- **Barras empilhadas:** `dim_produto[classe_abc]` × `% da Receita Líquida`, e o número de produtos por classe.
- **Tabela:** top 15 produtos com descrição, Receita Líquida e classe.

### Página 3 · Clientes (RFM)
- **Barras:** `dim_cliente[segmento]` × `Clientes` e `% da Receita Líquida`, lado a lado. Mostra que poucos clientes concentram a receita.
- **Dispersão:** eixo X = `dim_cliente[recencia_dias]` (Média), eixo Y = `dim_cliente[gasto_liquido]` (Soma), detalhes = `dim_cliente[id_cliente]`, legenda = `segmento`.
- **Tabela "Em risco":** filtre `segmento = Em risco` e mostre `id_cliente`, `pais`, `ultima_compra`, `frequencia` e `gasto_liquido`, ordenada pelo gasto. É a lista de ação para a reativação.

### Página 4 · Retenção (coortes)
- **Matriz:** linhas = `coortes[coorte]` (formato `yyyy-mm`), colunas = `coortes[mes_de_vida]`, valores = `coortes[retencao]` (agregação **Máximo**, formato porcentagem).
- Filtre `mes_de_vida` entre **1 e 12**.
- **Formatação condicional → Cor de fundo → Escala de cores** (branco para o menor, a cor principal para o maior). Vira o "mapa de calor" clássico de retenção.

### Página 5 · Devoluções
- **Cartões:** `Taxa de Devolução` e `Taxa de Devolução sem Gigantes`.
- **Linhas:** `dCalendario[Mes]` × `Taxa de Devolução sem Gigantes`.
- **Tabela:** `dim_produto[descricao]`, `Valor Devolvido`, `Taxa de Devolução`, ordenada pelo valor devolvido.

## 7. Conferir os números

Com nenhum filtro aplicado, os cartões devem mostrar:

| Medida | Valor esperado |
| --- | --- |
| Receita Bruta | £ 19.642.140 |
| Valor Devolvido | £ 716.426 |
| Pedidos | 39.516 |
| Clientes | 5.852 |
| Ticket Médio | £ 497 |
| Taxa de Devolução | 3,6% |
| Taxa de Devolução sem Gigantes | 2,4% |

Se algum número não bater, quase sempre é relacionamento faltando ou com direção errada na Exibição de modelo.

## 8. Antes de tirar os prints para o README

- [ ] Limpe todas as segmentações (**Ctrl + clique** em área vazia ou **Redefinir para o padrão**). Um filtro esquecido muda os números do print.
- [ ] Confira se os meses estão em ordem cronológica.
- [ ] Renomeie os campos nos visuais (clique duplo no nome em **Valores**). Nada de `product_category_name` ou `receita` em minúsculas na tela.
- [ ] Exporte em **Arquivo → Exportar → Exportar para PDF** ou recorte só a área do relatório, sem as barras do Power BI.
- [ ] Salve as imagens em `img/` (ex.: `img/dashboard_visao_geral.png`).
