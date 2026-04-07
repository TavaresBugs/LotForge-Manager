# Analise Comparativa: Drag & Drop do Painel — Position Sizer vs LotForge MenuPerf

## 1. Visao Geral

| Aspecto | Position Sizer (EarnForex) | LotForge MenuPerf (nosso) |
|---|---|---|
| Classe base | `CAppDialog` | `CAppDialog` (`CLotForgePanel`) |
| Linhas de codigo no OnChartEvent | ~40 (direto) | ~70 (com multiplos branches) |
| Estado global de drag | 2 variaveis (`remember_top/left`) | 10+ variaveis globais |
| Filtro CHART_CHANGE | `if (id != CHARTEVENT_CHART_CHANGE)` | Igual, mas com tratamento extra pesado |
| Overrides de drag | Nenhum (usa CAppDialog puro) | `OnDialogDragStart/End` com wrappers |

## 2. Como o Position Sizer Faz o Drag & Drop

### 2.1 Principio basico — Delegacao total ao CAppDialog

O Position Sizer usa uma estrategia de **delegacao minima**. Ele NAO intercepta o drag do painel de forma alguma — deixa o `CAppDialog` cuidar de tudo nativamente.

```mql5
// OnChartEvent — Posicao Sizer
if (id != CHARTEVENT_CHART_CHANGE)
{
    ExtDialog.OnEvent(id, lparam, dparam, sparam);
    if (id >= CHARTEVENT_CUSTOM) ChartRedraw();
}
```

Essa e a essencia: **um unico filtro** que impede o `CAppDialog.OnEvent` de ser chamado durante `CHARTEVENT_CHART_CHANGE` (workaround para um bug de minimizacao do MT5 ao trocar timeframe/simbolo). Fora isso, o CAppDialog gerencia:

- Deteccao de clique na barra de titulo
- Inicio/fim do arraste
- Movimentacao visual do painel
- Persistencia de posicao via INI file (`IniFileSave/IniFileLoad`)

### 2.2 Fixacao da posicao

O Position Sizer faz a persistencia de posicao de forma simples e eficaz:

```mql5
virtual void FixatePanelPosition()
{
    if (!m_minimized) m_norm_rect.SetBound(m_rect);
    else m_min_rect.SetBound(m_rect);
}
```

Isso diz ao CAppDialog para vincular o retangulo atual como "oficial", garantindo que apos o drag a posicao seja corretamente salva no INI file. E executado apos `Move()` e no fim do drag.

### 2.3 Variaveis de memoria

Apenas **duas variaveis** armazenam a posicao do painel:

```mql5
int remember_top, remember_left;
```

Elas sao atualizadas no fim do drag:

```mql5
if ((id == CHARTEVENT_CUSTOM + ON_DRAG_END) && (lparam == -1))
{
    ExtDialog.remember_top = ExtDialog.Top();
    ExtDialog.remember_left = ExtDialog.Left();
}
```

### 2.4 Contencao dentro do grafico

O Position Sizer faz contencao automatica do painel para que ele nao saia da area visivel:

```mql5
if (ExtDialog.Top() < 0) ExtDialog.Move(ExtDialog.Left(), 0);
if (ExtDialog.Top() > chart_height) ExtDialog.Move(ExtDialog.Left(), chart_height - ExtDialog.Height());
if (ExtDialog.Left() > chart_width) ExtDialog.Move(chart_width - ExtDialog.Width(), ExtDialog.Top());
```

Isso acontece dentro do handler de `CHARTEVENT_CHART_CHANGE`.

## 3. Como o LotForge MenuPerf Faz o Drag & Drop

### 3.1 Arquitetura complexa com multiplos layers

O LotForge intercepta o drag em **tres niveis** simultaneamente:

1. **CAppDialog hooks** — Override de `OnDialogDragStart()` e `OnDialogDragEnd()`
2. **Estado global manual** — `g_panel_dragging`, `g_ui_interaction_active`, `g_ui_interaction_quiet_until`
3. **Mouse move handler** — `HandleMouseMoveDrag()` com `DRAG_IDLE/DRAG_CANDIDATE/DRAG_ACTIVE_LINE`

```mql5
// Panel.mqh — overrides
bool CLotForgePanel::OnDialogDragStart(void)
  {
   BeginUiPanelDragInteraction();          // set g_panel_dragging = true
   return CAppDialog::OnDialogDragStart();
  }

bool CLotForgePanel::OnDialogDragEnd(void)
  {
   bool handled = CAppDialog::OnDialogDragEnd();
   EndUiPanelDragInteraction();            // set g_panel_dragging = false + quiet period
   RememberPanelPosition();
   return handled;
  }
```

### 3.2 Quantidade de estado global relacionado a drag

```mql5
// Estado de drag do painel
bool g_panel_dragging = false;

// Estado de interacao UI com time-throttle
bool g_ui_interaction_active = false;
ulong g_ui_interaction_quiet_until = 0;

// Estado de drag de linhas (separado do painel)
DragPhase g_drag_phase = DRAG_IDLE;
string g_drag_line_kind = "";
int g_drag_press_x = 0;
int g_drag_press_y = 0;

// Estado de handle interaction
bool g_handle_interaction_active = false;
bool g_native_handle_interaction_active = false;
ulong g_handle_interaction_quiet_until = 0;

// Scroll do chart
bool g_scroll_was_enabled = true;
bool g_scroll_suppressed = false;
```

Sao **11 variaveis globais** que precisam ser mantidas em sincronia vs 2 no Position Sizer.

## 4. Por que o Position Sizer e Mais Eficiente

### 4.1 Menos overhead por tick

| Metrica | Position Sizer | LotForge MenuPerf |
|---|---|---|
| Checks por tick no OnTick | 0 sobre drag | 3+ (`IsBackgroundInteractionActive()`, `IsPanelUiInteractionActive()`, `g_panel_dragging`) |
| Chamadas Object API durante drag | 0 | Muitas — o LotForge tenta suprimir updates mas ainda verifica condicoes |
| Redraws desnecessarios | Minimizado (so se `id >= CHARTEVENT_CUSTOM`) | Mais frequentes — `dispatch_redraw` triggera ChartRedraw mesmo durante drag |

### 4.2 Throttle por quiet period vs flag booleana

O Position Sizer nao precisa de "quiet period" para drag do painel porque confia 100% no CAppDialog. O LotForge usa um **quiet period com `GetTickCount64()`** para evitar atualizacoes logo apos interacoes:

```mql5
// LotForge — Management.mqh
void EndUiPanelDragInteraction(const uint quiet_ms)
  {
   g_panel_dragging = false;
   g_ui_interaction_quiet_until = GetTickCount64() + quiet_ms;
  }

bool IsPanelUiInteractionActive()
  {
   RefreshUiInteractionState();
   return g_ui_interaction_active;  // depende de g_panel_dragging || quiet period
  }
```

Esse quiet period cria uma **janela de cegueira** onde atualizacoes de preview sao suprimidas desnecessariamente por 120-180ms apos o drag terminar.

### 4.3 A raiz do problema: conflacao de responsabilidades

O LotForge trata **drag do painel** e **drag de linhas de preview** no mesmo sistema de estado:

- `g_drag_phase` (DRAG_IDLE / DRAG_CANDIDATE / DRAG_ACTIVE_LINE) — para drag de linhas
- `g_panel_dragging` — para drag do painel
- `g_handle_interaction_active` — para drag de overlay handles

No Position Sizer, esses mundos sao **separados**: o drag do painel e CAppDialog puro; o drag de linhas e tratado via `CHARTEVENT_OBJECT_DRAG` diretamente, sem estado global cruzado.

### 4.4 Supressao de scroll do chart

O LotForge tenta suprimir o scroll do chart durante interacoes com preview lines:

```mql5
void SuppressChartScroll() { ... }
void RestoreChartScroll() { ... }
```

Isso adiciona complexidade e potencial para bugs (scroll fica travado se o estado nao for restaurado corretamente). O Position Sizer **nao faz isso** — deixa o chart gerenciar seu proprio scroll naturalmente.

### 4.5 CHART_CHANGE handling

Ambos filtram `CHARTEVENT_CHART_CHANGE`, mas:

- **Position Sizer**: simplesmente nao passa o evento para `CAppDialog.OnEvent`. So isso.
- **LotForge**: alem do filtro, dentro do branch de `CHARTEVENT_CHART_CHANGE` faz: `RefreshPreviewFrameInvalidation()`, `UpdatePreview()`, `RefreshAllManagedTradeMarkers()` — trabalho pesado que poderia ser adiado.

## 5. Sugestoes de Melhorias para o LotForge

### 5.1 Simplificar o estado de drag do painel (prioridade alta)

Remover o wrapper `BeginUiPanelDragInteraction`/`EndUiPanelDragInteraction` e a flag `g_panel_dragging`. O CAppDialog ja sabe quando esta sendo arrastado. Em vez de trackear manualmente, confiar nos hooks `OnDialogDragStart/End` para fazer apenas o essencial:

- No `OnDialogDragStart`: apenas setar flag minima para pular preview updates no OnTick
- No `OnDialogDragEnd`: salvar posicao e atualizar preview UMA vez

Sugestao: reduzir de 3+ variaveis para 1 flag: `bool g_panel_is_being_dragged`.

### 5.2 Eliminar o quiet period para drag do painel (prioridade media)

O quiet period (`g_ui_interaction_quiet_until`) de 120-180ms apos o drag terminar e desnecessario para o proprio drag do painel. Ele pode ser mantido para interacoes de edicao (campos de texto), mas removido para o drag. Isso eliminaria a "janela de cegueira" onde o preview nao atualiza mesmo com preco mudando.

### 5.3 Separar drag do painel do drag de linhas (prioridade alta)

Criar dois subsistemas independentes:

- **PanelDrag** — totalmente delegado ao CAppDialog com uma flag booleana `g_panel_dragging`
- **LineDrag** — o sistema atual de `DragPhase`, `g_drag_line_kind`, etc. pode permanecer

Isso elimina a conflacao que faz `IsBackgroundInteractionActive()` verificar 3 flags diferentes quando deveria verificar apenas 2 mundos independentes.

### 5.4 Reduzir chamadas de Object API durante CHART_CHANGE (prioridade media)

No handler de `CHARTEVENT_CHART_CHANGE`, o LotForge chama `UpdatePreview()` e `RefreshAllManagedTradeMarkers()` mesmo durante o drag do painel (quando `!IsBackgroundInteractionActive()`). Estes sao ~150+ chamadas de Object API + ChartRedraw. O Position Sizer simplesmente nao faz nada durante CHART_CHANGE alem de verificar boundaries do painel.

Sugestao: marcar preview como "dirty" durante CHART_CHANGE e deixar o proximo tick cuidar do update, em vez de fazer o update sincrono.

### 5.5 Remover SuppressChartScroll / RestoreChartScroll (prioridade baixa)

Essa adicao introduz complexidade e risco de estado inconsistente. Se o scroll esta sendo suprimido para uma finalidade especifica (evitar scroll enquanto arrasta uma linha de preview), considerar se ha uma alternativa mais direta, como definir `OBJPROP_SELECTABLE` temporariamente.

### 5.6 Adotar o pattern de FixatePanelPosition do Position Sizer (prioridade baixa)

O Position Sizer tem:

```mql5
virtual void FixatePanelPosition()
{
    if (!m_minimized) m_norm_rect.SetBound(m_rect);
    else m_min_rect.SetBound(m_rect);
}
```

O LotForge tem codigo quase identico, mas espalhado em `RememberPanelPosition()`. Centralizar em um metodo com nome claro ajuda manutencao e deixa explicita a intencao.

## 6. Resumo Executivo

| Item | Situacao | Impacto |
|---|---|---|
| Excesso de estado global para drag | 11 variaveis vs 2 do PS | Alto — overhead, bugs de estado |
| Quiet period pos-drag | Cegueira de 120-180ms | Medio — preview nao atualiza |
| Conflacao panel-drag / line-drag | Flags cruzadas | Alto — logica dificil de rastrear |
| Trabalho sincrono no CHART_CHANGE | ~150 Object calls | Medio — lag visual durante drag |
| SuppressChartScroll manual | Complexidade extra | Baixo — risco de estado preso |

**Conclusao principal**: O Position Sizer e mais eficiente porque **confia no CAppDialog** para fazer o que ele foi projetado para fazer. O LotForge tenta controlar demais o processo de drag com estado global redundante, criando overhead desnecessario e oportunidades para inconsistencias de estado. A melhoria mais impactante seria simplificar o estado de drag para uma unica flag booleana e delegar o resto ao CAppDialog nativamente.
