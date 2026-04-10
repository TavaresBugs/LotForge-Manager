# LotForge Manager — MT5 Position Sizer & Trade Manager

LotForge Manager — painel de dimensionamento de posição e gerenciamento de trades para MetaTrader 5.

## Versão atual

- **v1.0** — Lançamento inicial
  - Position sizing automático (risco %, valor fixo na moeda da conta, lots)
  - Painel CAppDialog com drag nativo e layout compacto
  - Preview visual de TP, SL e entrada no gráfico
  - Gerenciamento automatizado: Break-Even, Trailing Stop, fechamento parcial
  - Managed Trade Markers — labels flutuantes por ticket (TP, SL, Mid Target, BE) com geometria escalável por zoom

## Funcionalidades

- **Position Sizing** — calcula lots automatic com base em risco %, valor fixo na moeda da conta, SL, ou lots
- **Painel CAppDialog** — interface com drag nativo, layout compacto de duas colunas
- **Preview visual** — linhas/zones de TP, SL e entrada no gráfico antes de confirmar a ordem
- **Gerenciamento automatizado** — Break-Even, Trailing Stop, e fechamento parcial
- **Managed Trade Markers** — labels flutuantes por ticket (TP, SL, Mid Target, BE) que acompanham a posição aberta em tempo real, ancorados por candles (escala dinâmica 8–256 dependendo do zoom)

## Arquitetura

| Camada | Descrição |
|--------|-----------|
| `BuildTradePlan → Validate → Send` | Pipeline de execução de trades |
| `CLotForgePanel : CAppDialog` | Painel de controles gerenciados com drag nativo |
| `Preview (PREV_PFX)` | Objetos visuais de montagem de ordem (OBJ_* no chart) |
| `Managed Markers (MNGD_PFX)` | Camada visual de posição aberta — independente do preview |
| `RunAutomatedTradeManagement()` | Auto BE, Trailing, Parcial |

## Camada de Posição Aberta

Cada ticket gerenciado exibe markers com informações financeiras reais:

- **TP** — preço, ganho estimado ($), % sobre saldo
- **SL** — preço, perda estimada ($), % sobre saldo
- **Mid Target** — gatilho parcial (desaparece após execução)
- **BE** — aparece apenas quando SL está genuinamente do lado do lucro

Geometria: largura dos markers se ajusta automaticamente ao zoom via `PreviewCandleCount()`.

## Estrutura do repo

```
LotForge_Manager.mq5            # EA principal (v1.0)
README.md                       # Este arquivo
```

## Instalação

1. Copie `LotForge_Manager.mq5` para `MQL5/Experts/` do seu terminal MT5
2. Compile no MetaEditor (F7)
3. Arraste o EA para qualquer gráfico no MT5

## Notas

- A base do `%` financeiro usa `ACCOUNT_BALANCE`
