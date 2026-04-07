# Comparativo Completo: LotForge vs Position Sizer — Plot do Menu, Drag & Drop e Performance

## Sumario

1. [Arquitetura do Painel](#1-arquitetura-do-painel)
2. [Layout e Plot dos Controles](#2-layout-e-plot-dos-controles)
3. [Drag & Drop do Painel](#3-drag--drop-do-painel)
4. [Drag das Linhas de Preview (Entry/SL/TP)](#4-drag-das-linhas-de-preview)
5. [Sistema de Overlay Labels (Position-Sizer style)](#5-sistema-de-overlay-labels)
6. [Event Loop e OnChartEvent](#6-event-loop-e-onchartevent)
7. [Update do Preview no OnTick](#7-update-do-preview-no-ontick)
8. [Refresh dos Valores do Painel](#8-refresh-dos-valores-do-painel)
9. [Gerenciamento de Estado](#9-gerenciamento-de-estado)
10. [Sugestoes de Melhorias](#10-sugestoes-de-melhorias)

---

## 1. Arquitetura do Painel

### Position Sizer

```
CPositionSizeCalculator : public CAppDialog
├── 5 CPanelList* (MainTabList, RiskTabList, MarginTabList, SwapsTabList, TradingTabList)
├── ~60 controles (CEdit, CButton, CLabel, CCheckBox, CHorizontalRadioGroup)
├── Sistema de ABAS (tabs) — Main / Risk / Margin / Swaps / Trading
├── OutsideTradeButton (fora do CAppDialog, posicionado livremente)
├── Criação via helpers: ButtonCreate(), EditCreate(), LabelCreate(), CheckBoxCreate()
└── Cria controles DENTRO do CAppDialog via Add()
```

**Como funciona**: Cada aba e um grupo de controles que sao mostrados/ocultados via `ShowMain()`, `ShowRisk()`, etc. O `CreateObjects()` cria todos os controles de uma vez, e `InitObjects()` os inicializa.

### LotForge

```
CLotForgePanel : public CAppDialog
├── Sem abas — painel unico plano
├── ~20 controles (CEdit, CButton)
├── Layout de 2 colunas: [Lots/Risk%+Entry] [TP+SL]
├── Criação manual inline: CreateInlineGroup(), CreateRiskModeGroup()
├── Preview objects SEPARADOS do CAppDialog (chart-space OBJ_HLINE, OBJ_RECTANGLE)
└── Gerenciamento de posicao por polling de Left()/Top()
```

**Como funciona**: Painel simples e plano, sem abas. Controles criados diretamente em `CreatePanel()`. Preview vive no chart como objetos separados.

### Diferenca Crucial

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| Abas | 5 abas com `CPanelList*` | Nenhuma — painel plano |
| Total de controles | ~60 | ~20 |
| Helpers de criacao | `ButtonCreate()`, `EditCreate()`, etc. (registra em `CList*`) | `CreateInlineGroup()` manual |
| `CList*` para tracking | Sim — todos os controles registrados | Nao |
| Outside controls | `m_OutsideTradeButton` (fora do CAppDialog) | Nenhum |
| Persistencia | INI file via `IniFileSave/IniFileLoad` (nativo CAppDialog) | Global Variables via `GlobalVariableSet/Get` |

---

## 2. Layout e Plot dos Controles

### Como o Position Sizer Plota

**Principio**: Layout baseado em **variaveis de layout computadas** no `InitObjects()`. Ele calcula:

```mql5
first_column_start, normal_label_width, normal_edit_width, second_column_start,
element_height, third_column_start, narrow_label_width, multi_tp_column_start,
multi_tp_label_width, multi_tp_button_start, leverage_edit_width,
third_trading_column_start, second_trading_column_start
```

Essas variaveis sao calculadas uma vez no `InitObjects()` e reusadas para posicionar TODOS os controles. O posicionamento segue um padrao vertical linear:

```
Y cursor sobe a cada grupo: cy += element_height + v_spacing
```

Cada aba tem sua propria logica de posicionamento, mas todos seguem o mesmo padrao. Exemplo do Main tab:

```
[Order Type] [Long/Short]
[Entry Level] [+/-]
[Stop Loss] [+/-]
[Take Profit] [+/-]
[Position Size]
[Account Size]
[Risk % Input] → [Result]
[Risk $ Input] → [Result]
```

Os controles de resultado sao **CEdit read-only** dentro do proprio CAppDialog — nao precisam de objetos chart externos.

### Como o LotForge Plota

Layout compacto de 2 colunas com coordenadas hardcoded:

```
Row 1: [RiskMode/Lots  val  ±]    [Entry  val  ±]
Row 2: [TP  val  ±]                [SL  val  ±]
Row 3: [Sell]                      [Buy]
Row 4: [Sell Pending]              [Buy Pending]
Row 5: [BE amber]                  [Trailing purple]
Row 6: [☐ Auto BE]                [☐ Auto Trailing]
Row 7: [☐ Algo Trading           (full-width)]
Row 8: [Cancel]                    [Send]
```

Constantes de layout fixas:

```mql5
PANEL_W = 340, PANEL_H = 328
ROW_H = 22, ROW_GAP = 2, LABEL_W = 52, EDIT_W = 97
ACTION_BTN_H = 28
```

### Comparacao

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| Flexibilidade | Layout computado — adapta a conteudo | Constantes fixas — fragil a mudancas |
| Informacao no painel | Resultados ($, %, RR) dentro do painel | Resultados apenas no overlay do chart |
| Abas | Separa configuracao de trading | Tudo visivel o tempo todo |
| Complexidade visual | Alta, mas organizado | Baixa, compacto |
| DPI awareness | Variaveis computadas do client area | `ClientAreaWidth()` usado corretamente |

**Onde o Position Sizer e melhor**: Os resultados financeiros (risk $, reward $, RR%) sao exibidos **dentro do painel** como campos read-only, atualizados em tempo real via `RefreshValues()`. O usuario nao precisa olhar para o chart para ver o risco em dolares — tudo esta no painel.

**Onde o LotForge compensa**: O layout e muito mais simples e leve. Menos objetos = menos overhead. Os resultados aparecem nos overlay labels do chart (Position-Sizer style), que sao visuais e contextuais.

---

## 3. Drag & Drop do Painel

### Position Sizer — Delegacao Total ao CAppDialog

**Como funciona (simples)**:

```mql5
// OnChartEvent — Position Sizer
if (id != CHARTEVENT_CHART_CHANGE)
{
    ExtDialog.OnEvent(id, lparam, dparam, sparam);
    if (id >= CHARTEVENT_CUSTOM) ChartRedraw();
}
```

Isso e **tudo** que o Position Sizer faz para drag do painel. O `CAppDialog.OnEvent()` internamente:

1. Detecta mouse down na barra de titulo (caption)
2. Inicia drag nativo — o MT5 move o painel visualmente
3. Ao soltar, `OnDialogDragEnd()` e chamado internamente
4. Posicao e salva via `IniFileSave()` (arquivo .ini na pasta Files)

**Persistencia de posicao**:

```mql5
// No fim do drag:
if ((id == CHARTEVENT_CUSTOM + ON_DRAG_END) && (lparam == -1))
{
    ExtDialog.remember_top = ExtDialog.Top();
    ExtDialog.remember_left = ExtDialog.Left();
}
```

Apenas **2 variaveis** (`remember_top`, `remember_left`). Sem polling. Sem flags. Sem quiet period.

**Fixacao da posicao**:

```mql5
virtual void FixatePanelPosition()
{
    if (!m_minimized) m_norm_rect.SetBound(m_rect);
    else m_min_rect.SetBound(m_rect);
}
```

Isso vincula o retangulo atual como "oficial" para o INI file. Chamado apos `Move()`.

### LotForge — Polling + Flag Manual

**Como funciona (complexo)**:

```mql5
// OnChartEvent — LotForge
if (id == CHARTEVENT_MOUSE_MOVE)
{
    // Polling: compara Left()/Top() a cada MOUSE_MOVE
    int px = (int)g_panel.Left();
    int py = (int)g_panel.Top();
    if(g_panel_last_x >= 0 && (px != g_panel_last_x || py != g_panel_last_y))
    {
        g_panel_dragging = true;   // detectou drag por polling!
        g_panel_last_x = px;
        g_panel_last_y = py;
        return;
    }
    g_panel_last_x = px;
    g_panel_last_y = py;

    // Detecta fim do drag
    if(!btn_down && g_panel_dragging)
    {
        g_panel_dragging = false;
        UpdatePreview();   // refresh uma vez
        ChartRedraw(0);
        return;
    }

    HandleMouseMoveDrag(lparam, dparam, btn_down);
}
```

O LotForge usa **polling** para detectar drag: a cada `CHARTEVENT_MOUSE_MOVE`, compara `Left()/Top()` com os valores anteriores. Se mudou, seta `g_panel_dragging = true`.

**Variaveis de estado de drag no LotForge**:

```mql5
bool    g_panel_dragging = false;
int     g_panel_last_x = -1;
int     g_panel_last_y = -1;
```

### Comparacao Direta

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| Deteccao de drag | Nativa (CAppDialog interno) | Polling de Left()/Top() a cada MOUSE_MOVE |
| Variaveis de estado | 2 (`remember_top/left`) | 3 (`g_panel_dragging`, `g_panel_last_x/y`) |
| Chamadas de API por frame | 0 (CAppDialog faz tudo) | 2 (`g_panel.Left()`, `g_panel.Top()`) |
| Fim do drag | `ON_DRAG_END` event | Detecta `btn_down == false` no MOUSE_MOVE |
| Persistencia | INI file nativo (`IniFileSave`) | Global Variables (`GlobalVariableSet`) |
| Overhead durante drag | Zero | Polling + checks no OnTick (`!g_panel_dragging`) |

**Por que o Position Sizer e mais eficiente aqui**:

1. **Zero polling** — o CAppDialog ja sabe quando esta sendo arrastado internamente. O LotForge desperdica 2 chamadas `ObjectGetInteger` (via `Left()/Top()`) em **cada** `CHARTEVENT_MOUSE_MOVE`.
2. **Sem estado extra** — nao precisa de flags globais para saber se esta arrastando. O CAppDialog cuida disso.
3. **Event-driven vs poll-driven** — o Position Sizer responde a `ON_DRAG_END`, o LotForge fica verificando `btn_down` a cada frame.

---

## 4. Drag das Linhas de Preview (Entry/SL/TP)

### Position Sizer — Nativo via `CHARTEVENT_OBJECT_DRAG`

**Linhas sao OBJ_HLINE com `OBJPROP_SELECTABLE = true`**:

```mql5
// Criacao das linhas
ObjectSetInteger(ChartID(), ObjectPrefix + "StopLossLine", OBJPROP_SELECTABLE, true);
ObjectSetInteger(ChartID(), ObjectPrefix + "StopLossLine", OBJPROP_SELECTED, sets.WasSelectedStopLossLine);
```

O MT5 cuida do drag visual nativamente. Quando o usuario solta:

```mql5
// OnChartEvent — Position Sizer
if ((id == CHARTEVENT_OBJECT_DRAG) &&
    ((sparam == ObjectPrefix + "EntryLine") ||
     (sparam == ObjectPrefix + "StopLossLine") ||
     (StringFind(sparam, ObjectPrefix + "TakeProfitLine") != -1) ||
     (sparam == ObjectPrefix + "StopPriceLine")))
{
    // Le o novo preco da linha arrastada
    if (sparam == ObjectPrefix + "StopLossLine") ExtDialog.UpdateFixedSL();
    else if (sparam == ObjectPrefix + "TakeProfitLine") ExtDialog.UpdateFixedTP();

    ExtDialog.RefreshValues();
    ChartRedraw();
}
```

**Simples e limpo**:
- O MT5 move a linha visualmente durante o drag (zero trabalho do EA)
- Ao soltar, `CHARTEVENT_OBJECT_DRAG` dispara UMA vez
- Le `ObjectGetDouble(..., OBJPROP_PRICE)` e atualiza o estado
- Chama `RefreshValues()` para atualizar o painel

### LotForge — Hibrido: Nativo + Overlay Bar Mouse Drag

**Linhas tambem sao OBJ_HLINE selectables**:

```mql5
ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);  // native drag
ObjectSetInteger(0, name, OBJPROP_BACK, false);       // foreground
```

**Path 1 — Drag nativo via `CHARTEVENT_OBJECT_DRAG`**:

```mql5
if(id == CHARTEVENT_OBJECT_DRAG)
{
    HandleNativeLineDrag(sparam);  // le OBJPROP_PRICE, atualiza g_state
    return;
}
```

Mesmo padrao do Position Sizer — limpo e eficiente.

**Path 2 — Drag via overlay bars (OBJ_RECTANGLE_LABEL)**:

```mql5
if(id == CHARTEVENT_MOUSE_MOVE)
{
    HandleMouseMoveDrag(lparam, dparam, btn_down);
}

// Inside HandleMouseMoveDrag:
// 1. Detecta hit nos overlay bars via DetectOverlayBarHit()
// 2. Se hit e btn_down → DRAG_CANDIDATE → threshold → DRAG_ACTIVE_LINE
// 3. AplicaLineDrag() a cada frame de mouse move
```

Os overlay bars (`_ovbg`) sao `OBJ_RECTANGLE_LABEL` que flutuam sobre as linhas. Eles **nao sao selectable**, entao o LotForge implementa seu proprio drag via `MOUSE_MOVE`:

1. `DetectOverlayBarHit(mx, my)` — hit test nos retangulos
2. Se hit → `SuppressChartScroll()` + `DRAG_CANDIDATE`
3. Move além do threshold → `DRAG_ACTIVE_LINE`
4. A cada mouse move → `ApplyLineDrag(mx, my)` → `UpdatePreview()`

### Comparacao

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| Drag de linhas | 100% nativo (`OBJECT_DRAG`) | Hibrido: nativo + overlay bar mouse drag |
| Overlay bars | Nao tem (labels sao OBJ_LABEL no chart) | `OBJ_RECTANGLE_LABEL` arrastaveis via MOUSE_MOVE |
| Scroll suprimido durante drag | Nao | Sim (`SuppressChartScroll()`) |
| Hit test manual | Nao | Sim (`DetectOverlayBarHit`) |
| Update durante drag de overlay | `RefreshValues()` a cada frame | `UpdatePreview()` a cada frame (caro!) |

**Onde o Position Sizer e melhor**: Linhas de preview sao draggadas nativamente pelo MT5 — zero overhead durante o drag. O update so acontece UMA vez ao soltar.

**Onde o LotForge sofre**: O overlay bar drag (`HandleMouseMoveDrag`) chama `UpdatePreview()` **a cada frame** de mouse move, que sao ~150+ chamadas de Object API + `ChartRedraw()` por frame. Isso causa lag visivel.

---

## 5. Sistema de Overlay Labels

### Position Sizer — Labels como OBJ_LABEL no chart

O Position Sizer usa **OBJ_LABEL** com `OBJPROP_BACK = false` para exibir infos ao lado das linhas:

```mql5
// Label posicionado com CORNER_LEFT_UPPER + XDISTANCE/YDISTANCE
ObjectCreate(ChartID(), ObjectPrefix + "StopLossLabel", OBJ_LABEL, 0, 0, 0);
ObjectSetInteger(ChartID(), ObjectPrefix + "StopLossLabel", OBJPROP_CORNER, CORNER_LEFT_UPPER);
ObjectSetInteger(ChartID(), ObjectPrefix + "StopLossLabel", OBJPROP_XDISTANCE, x);
ObjectSetInteger(ChartID(), ObjectPrefix + "StopLossLabel", OBJPROP_YDISTANCE, y);
ObjectSetString(ChartID(), ObjectPrefix + "StopLossLabel", OBJPROP_TEXT, label);
```

Os labels sao **simples** — apenas texto posicional. Nao sao arrastaveis. A posicao Y e derivada do preco via `ChartPriceToY()`, a posicao X e fixa ou calculada.

### LotForge — Overlay bars estilo Position Sizer (OBJ_RECTANGLE_LABEL + OBJ_LABEL)

O LotForge implementa o que chama de "Position-Sizer style" overlay:

```mql5
// Par de objetos: background bar + texto
UpdateOverlayPreviewLabel("tp", "TP 1.08500 | +$15.00", tp_price, t1, t2,
                          true,  // acima da linha
                          CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
```

Cria dois objetos:
- `OBJ_RECTANGLE_LABEL` (barra de fundo)
- `OBJ_LABEL` (texto dentro da barra)

Posicionados na borda direita do range de preview (`t1..t2`), ancorados ao preco.

**Fast-path de performance**:

```mql5
// Se so a posicao mudou (preco mudou) mas texto igual → so atualiza DISTANCE
if(prev_text == text)
{
    // ~4 ObjectSet calls em vez de ~13 + font loop
    ObjectSetInteger(0, bg_n, OBJPROP_XDISTANCE, bar_x);
    ObjectSetInteger(0, bg_n, OBJPROP_YDISTANCE, box_y);
    return;
}
```

Se o texto mudou, faz rebuild completo com `TextSetFont()`/`TextGetSize()` loop para ajustar font size.

### Comparacao

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| Tipo de objeto | `OBJ_LABEL` simples | `OBJ_RECTANGLE_LABEL` + `OBJ_LABEL` par |
| Background | Nenhum (texto puro) | Barra colorida com borda |
| Posicao | Derivada do preco | ChartTimePriceToXY + screen coords |
| Fast-path | Nao | Sim (position-only update) |
| Adaptive font | Nao | Sim (shrink until fits) |
| Drag do label | Nao (e so visual) | Sim (via `HandleMouseMoveDrag`) |

**Onde o Position Sizer e melhor**: Labels sao mais leves — apenas `OBJ_LABEL` sem background. Menos objetos para renderizar.

**Onde o LotForge e melhor**: Labels sao mais visuais e informativos. O fast-path de position-only update economiza chamadas de API quando so o preco muda.

---

## 6. Event Loop e OnChartEvent

### Position Sizer

```mql5
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // 1. MOUSE_MOVE — tracking de posicao para hotkeys
    if (id == CHARTEVENT_MOUSE_MOVE)
    {
        Mouse_Last_X = (int)lparam;
        Mouse_Last_Y = (int)dparam;
        // So verifica linhas sendo movidas (fixed SL/TP mode)
        if (((uint)sparam & 1) == 1) { ... }
    }

    // 2. OBJECT_CLICK — clicks em Edits
    if (id == CHARTEVENT_OBJECT_CLICK) { ... }

    // 3. CLICK — reset flags
    if (id == CHARTEVENT_CLICK) { ... }

    // 4. DRAG_END — persiste posicao do painel
    if ((id == CHARTEVENT_CUSTOM + ON_DRAG_END) && (lparam == -1)) { ... }

    // 5. OBJECT_ENDEDIT / ON_CLICK — multiplos TP fields
    if (id == CHARTEVENT_OBJECT_ENDEDIT) { ... }

    // 6. KEYDOWN — hotkeys (Shift+T, S, P, E, etc.)
    if (id == CHARTEVENT_KEYDOWN) { ... }

    // 7. Delega ao CAppDialog (exceto CHART_CHANGE)
    if (id != CHARTEVENT_CHART_CHANGE)
    {
        ExtDialog.OnEvent(id, lparam, dparam, sparam);
        if (id >= CHARTEVENT_CUSTOM) ChartRedraw();
    }

    // 8. CHART_CHANGE / CLICK / OBJECT_DRAG — recalcula
    if ((id == CHARTEVENT_CLICK) || (id == CHARTEVENT_CHART_CHANGE) ||
        ((id == CHARTEVENT_OBJECT_DRAG) && (line objects)))
    {
        // Le novas posicoes das linhas, atualiza fixed SL/TP
        ExtDialog.RefreshValues();
        ChartRedraw();
    }
}
```

**Caracteristicas**:
- ~35 linhas de logica no OnChartEvent
- Sem branching complexo
- Delegacao limpa ao CAppDialog
- Hotkeys nativos (Shift+T, S, P, E)

### LotForge

```mql5
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // 1. Filtra CHART_CHANGE do CAppDialog
    if(id != CHARTEVENT_CHART_CHANGE)
        g_panel.ChartEvent(id, lparam, dparam, sparam);

    // 2. CHART_CHANGE — update preview + markers
    if(id == CHARTEVENT_CHART_CHANGE)
    {
        if(!g_panel_dragging) { UpdatePreview(); RefreshAllManagedTradeMarkers(); }
        return;
    }

    // 3. OBJECT_DRAG — line drag nativo
    if(id == CHARTEVENT_OBJECT_DRAG) { HandleNativeLineDrag(sparam); return; }

    // 4. OBJECT_CLICK — deselect lines
    if(id == CHARTEVENT_OBJECT_CLICK) { ... return; }

    // 5. MOUSE_MOVE — panel drag detection + line drag
    if(id == CHARTEVENT_MOUSE_MOVE)
    {
        // Polling de posicao do painel
        int px = (int)g_panel.Left();
        int py = (int)g_panel.Top();
        if(px != g_panel_last_x || py != g_panel_last_y) { g_panel_dragging = true; return; }

        // Detecta fim do drag
        if(!btn_down && g_panel_dragging) { UpdatePreview(); ChartRedraw(); return; }

        // Overlay bar drag
        HandleMouseMoveDrag(lparam, dparam, btn_down);
        return;
    }
}
```

**Caracteristicas**:
- ~80 linhas de logica no OnChartEvent
- Branching complexo com multiplos `return`
- Polling de posicao a cada MOUSE_MOVE
- Dois sistemas de drag coexistindo (nativo + overlay bar)

### Comparacao

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| Linhas de codigo | ~35 | ~80 |
| Branches com return | 3-4 | 8+ |
| Polling de estado | Nao | Sim (Left/Top a cada frame) |
| Sistemas de drag | 1 (nativo) | 2 (nativo + overlay bar) |
| Hotkeys | Sim (Shift+T, S, P, E) | Nao |
| `ChartRedraw()` calls | 1-2 por evento | 1-3 por evento |

---

## 7. Update do Preview no OnTick

### Position Sizer

```mql5
void OnTick()
{
    ExtDialog.RefreshValues();  // So atualiza valores do painel

    if (sets.TrailingStopPoints > 0) DoTrailingStop();
}
```

**Nao faz update de preview no OnTick**. Os valores do painel sao atualizados via `RefreshValues()` que so toca os CEdit members — zero Object API calls externas. O preview visual das linhas e atualizado apenas quando as linhas sao arrastadas (`CHARTEVENT_OBJECT_DRAG`) ou quando o chart muda (`CHARTEVENT_CHART_CHANGE`).

### LotForge

```mql5
void OnTick()
{
    // Throttle por preco: so update se entry/sl/tp mudou
    if(g_state.action != ACTION_NONE && !g_panel_dragging)
    {
        double entry_now = ...;
        double sl_now = ...;
        double tp_now = ...;

        if(entry_now != g_last_preview_entry ||
           sl_now    != g_last_preview_sl    ||
           tp_now    != g_last_preview_tp)
        {
            g_last_preview_entry = entry_now;
            g_last_preview_sl    = sl_now;
            g_last_preview_tp    = tp_now;
            UpdatePreview();  // ~150+ Object API calls + ChartRedraw
        }
    }

    SyncManagedTradeState();
    RunAutomatedTradeManagement();
    RefreshAllManagedTradeMarkers();  // Mais Object API calls
}
```

**O LotForge faz muito mais no OnTick**:
1. Throttle por preco (bom)
2. `UpdatePreview()` — cria/atualiza 3 OBJ_HLINE + 3 zonas + 3 overlay labels
3. `SyncManagedTradeState()` — itera posicoes abertas
4. `RunAutomatedTradeManagement()` — BE/Trailing/Parcial logic
5. `RefreshAllManagedTradeMarkers()` — scan de objetos + update de markers

### Comparacao

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| OnTick trabalho | `RefreshValues()` (so CEdit) | Preview + Management + Markers |
| Object API calls no OnTick | 0 | ~200+ (sem throttle) / ~150+ (com throttle) |
| Throttle | Nao precisa (sem preview no OnTick) | Sim (por preco) |
| Skip durante drag | N/A (sem preview no OnTick) | Sim (`!g_panel_dragging`) |
| Timer | `ExtDialog.RefreshValues()` + `ChartRedraw()` | `UpdatePreview()` se dirty |

**Onde o Position Sizer e muito melhor**: Nao faz trabalho pesado no OnTick. O preview visual sao as proprias linhas OBJ_HLINE no chart — o MT5 as renderiza nativamente, sem codigo do EA. Quando o preco de mercado muda, as linhas NAO se movem (elas sao niveis fixos definidos pelo usuario). Entao nao ha nada para atualizar no OnTick.

**Onde o LotForge sofre**: Mesmo com throttle, `UpdatePreview()` faz ~150 chamadas de Object API quando o preco muda. Em mercado volatil, isso pode ocorrer varios ticks por segundo.

---

## 8. Refresh dos Valores do Painel

### Position Sizer — `RefreshValues()`

Atualiza os **CEdit members** do CAppDialog com valores calculados. Como os controles sao members da classe, o update e direto:

```mql5
void CPositionSizeCalculator::RefreshValues()
{
    // Calcula tudo internamente
    // Atualiza m_EdtPosSize.Text(), m_EdtRiskPRes.Text(), etc.
    // So toca objetos que sao parte do CAppDialog
}
```

### LotForge — `RefreshValues()` + `UpdatePreview()`

Atualiza os CEdit members E TAMBEM os objetos chart externos:

```mql5
void CLotForgePanel::RefreshValues()
{
    m_EdtPrimary.Text(prim_text);
    m_EdtEntry.Text(entry_text);
    m_EdtTP.Text(tp_text);
    m_EdtSL.Text(sl_text);
}
```

Mas em muitos handlers (ex: `OnClickPrimaryUp`), faz:

```mql5
RefreshValues(); UpdatePreview(); ChartRedraw(0);
```

**O LotForge faz triplo trabalho** onde o Position Sizer faz um: `RefreshValues()` + `UpdatePreview()` + `ChartRedraw(0)` vs apenas `RefreshValues()`.

### Comparacao

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| Update de controles | So CEdit members | CEdit + chart objects |
| ChartRedraw por click | 1 (via OnEvent) | 1-3 (explicit calls) |
| Resultados financeiros | No painel (CEdit read-only) | No chart (overlay labels) |
| Separacao de concerns | Limpa (painel != chart) | Misturada (painel atualiza chart) |

---

## 9. Gerenciamento de Estado

### Position Sizer

```mql5
// Estado: variaveis globais minimalistas
double EntryLevel, StopLossLevel, TakeProfitLevel, StopPriceLevel;
bool StopLossLineIsBeingMoved = false;
bool TakeProfitLineIsBeingMoved[];
int Mouse_Last_X, Mouse_Last_Y;
// + struct `sets` (carregada do disco)
```

Estado do painel e persistido via **INI file** (mecanismo nativo do CAppDialog):
- `IniFileSave()` — salva posicao/minimized state
- `IniFileLoad()` — restaura posicao/minimized state

Settings personalizados sao salvos em **arquivo .txt** separado (`SaveSettingsOnDisk`).

### LotForge

```mql5
// Estado: struct PanelState + variaveis globais
PanelState    g_state;                    // ~20 campos
TradeParams   g_trade_plan;               // 10 campos
DragPhase     g_drag_phase;               // enum
string        g_drag_line_kind;
int           g_drag_press_x, g_drag_press_y;
bool          g_panel_dragging;
int           g_panel_last_x, g_panel_last_y;
double        g_last_preview_entry, g_last_preview_sl, g_last_preview_tp;
bool          g_scroll_was_enabled, g_scroll_suppressed, g_status_sticky;
ManagedTradeState g_managed_trades[];     // array dinamico
bool          g_algo_trading_enabled;
```

Persistencia via **Global Variables** do terminal:
- `SaveStateForChartChange()` — 11 `GlobalVariableSet()` calls
- `RestoreStateFromChartChange()` — 11 `GlobalVariableGet()` calls + `GlobalVariableDel()`

### Comparacao

| Aspecto | Position Sizer | LotForge |
|---|---|---|
| Variaveis de estado globais | ~8 | ~15+ |
| Struct de estado | `sets` (settings) | `g_state` (PanelState, 20+ campos) |
| Persistencia posicao | INI file (nativo CAppDialog) | Global Variables (terminal GV) |
| Persistencia settings | Arquivo .txt customizado | Nao tem (hardcoded no painel) |
| Estado de drag | 2 variaveis | 5+ variaveis |
| Gestao de posicoes | N/A (so sizing) | `ManagedTradeState[]` array |

---

## 10. Sugestoes de Melhorias

### 10.1 Eliminar Polling de Drag do Painel (Prioridade: ALTA)

**Problema**: O LotForge faz polling de `g_panel.Left()/Top()` a cada `CHARTEVENT_MOUSE_MOVE` para detectar drag.

**Solucao**: Usar o padrao do Position Sizer — confiar no CAppDialog. Remover `g_panel_last_x/y` e a detecao por polling no MOUSE_MOVE. O drag do painel e gerenciado internamente pelo CAppDialog; nao precisamos detecta-lo.

```mql5
// ANTES (no OnChartEvent MOUSE_MOVE):
int px = (int)g_panel.Left();
int py = (int)g_panel.Top();
if(g_panel_last_x >= 0 && (px != g_panel_last_x || py != g_panel_last_y)) {
    g_panel_dragging = true;
    return;
}

// DEPOIS: remover tudo. O CAppDialog ja sabe que esta sendo arrastado.
// Para skip de update durante drag, usar override OnDialogDragStart/End:
bool CLotForgePanel::OnDialogDragStart() { g_skip_updates = true;  return CAppDialog::OnDialogDragStart(); }
bool CLotForgePanel::OnDialogDragEnd()   { g_skip_updates = false; return CAppDialog::OnDialogDragEnd(); }
```

### 10.2 Unificar o Sistema de Drag de Linhas (Prioridade: ALTA)

**Problema**: LotForge tem DOIS sistemas de drag de linhas coexistindo:
1. Nativo via `CHARTEVENT_OBJECT_DRAG` (bom)
2. Overlay bar drag via `HandleMouseMoveDrag` (pesado)

**Solucao**: Tornar as overlay bars **nao-draggaveis**. Elas devem ser apenas visuais (labels informativos). O drag das linhas deve ser 100% nativo via `CHARTEVENT_OBJECT_DRAG`, igual ao Position Sizer.

Remover:
- `DetectOverlayBarHit()` — hit test desnecessario
- `HandleMouseMoveDrag()` — drag manual pesado
- `DRAG_CANDIDATE` / `DRAG_ACTIVE_LINE` — fases desnecessarias
- `SuppressChartScroll()` / `RestoreChartScroll()` — scroll hack

Manter apenas:
- `HandleNativeLineDrag()` — le `OBJPROP_PRICE` ao soltar
- Linhas `OBJ_HLINE` com `OBJPROP_SELECTABLE = true`

### 10.3 Reduzir `UpdatePreview()` no OnTick (Prioridade: MEDIA)

**Problema**: Mesmo com throttle por preco, `UpdatePreview()` faz ~150 chamadas de API quando dispara.

**Solucao**: Adotar o padrao do Position Sizer — **nao fazer update de preview no OnTick**. As linhas OBJ_HLINE sao objetos chart que o MT5 renderiza nativamente. So atualize quando:
1. Usuario muda um valor no painel (via evento de click/edit)
2. Linha e arrastada (via `CHARTEVENT_OBJECT_DRAG`)
3. Chart muda (via `CHARTEVENT_CHART_CHANGE`)

No OnTick, apenas atualize o preco de entry para ordens a mercado (se necessario).

### 10.4 Adotar INI File para Persistencia (Prioridade: MEDIA)

**Problema**: LotForge usa Global Variables para persistir posicao do painel. GVs sao lentos e podem colidir entre instancias.

**Solucao**: Usar `IniFileSave()`/`IniFileLoad()` do CAppDialog, igual ao Position Sizer. O CAppDialog ja tem suporte nativo para isso.

```mql5
// No OnDeinit (non-chart-change):
g_panel.IniFileSave();

// No OnInit, apos Create/Run:
g_panel.IniFileLoad();
```

### 10.5 Exibir Resultados Financeiros no Painel (Prioridade: BAIXA)

**Problema**: LotForge mostra risco $, reward $, e RR% apenas nos overlay labels do chart.

**Solucao**: Adicionar campos read-only no painel (estilo Position Sizer) para mostrar:
- Risk: `$X.XX (X.XX%)`
- Reward: `$X.XX (X.XX%)`
- R:R: `1:X.XX`

Isso daria ao usuario feedback financeiro imediato sem precisar olhar para o chart. Os overlay labels poderiam permanecer como complemento visual.

### 10.6 Adicionar Hotkeys (Prioridade: BAIXA)

O Position Sizer tem hotkeys nativos:
- `Shift+T` — executar trade
- `S` — set SL onde o mouse esta
- `P` — set TP onde o mouse esta
- `E` — set Entry onde o mouse esta
- `H` — hide/show lines
- `` ` `` — minimize/maximize

O LotForge poderia adicionar atalhos basicos:
- `B` — selecionar Buy
- `S` — selecionar Sell
- `Enter` — Send order
- `Esc` — Cancel
- `` ` `` — minimize/maximize

### 10.7 Simplificar OnChartEvent (Prioridade: MEDIA)

**Problema**: 80 linhas com 8+ branches e returns no OnChartEvent.

**Solucao**: Reestruturar para o padrao do Position Sizer:

```mql5
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // 1. Native line drag
    if(id == CHARTEVENT_OBJECT_DRAG) { HandleNativeLineDrag(sparam); return; }

    // 2. Chart change
    if(id == CHARTEVENT_CHART_CHANGE) {
        UpdatePreview();
        RefreshAllManagedTradeMarkers();
        return;
    }

    // 3. Mouse move (so for hover/interaction detection)
    if(id == CHARTEVENT_MOUSE_MOVE) { return; }

    // 4. Delegate to panel
    if(id != CHARTEVENT_CHART_CHANGE)
        g_panel.ChartEvent(id, lparam, dparam, sparam);

    if(id >= CHARTEVENT_CUSTOM)
        ChartRedraw(0);
}
```

---

## Resumo Executivo: Pontuacao por Categoria

| Categoria | Position Sizer | LotForge | Diferenca |
|---|---|---|---|
| **Drag do painel** | 10/10 — nativo, zero overhead | 5/10 — polling manual | PS delega ao CAppDialog; LF faz polling |
| **Drag das linhas** | 9/10 — 100% nativo | 7/10 — nativo + overlay bar manual | PS tem um sistema; LF tem dois conflitando |
| **Event Loop** | 9/10 — limpo, 35 linhas | 5/10 — complexo, 80 linhas | PS tem menos branches e returns |
| **OnTick performance** | 10/10 — zero Object API | 5/10 — ~150 calls com throttle | PS nao faz preview no OnTick |
| **Overlay labels** | 7/10 — simples, leves | 7/10 — visuais, fast-path | PS = simples; LF = bonito mas pesado |
| **Persistencia** | 9/10 — INI file nativo | 6/10 — Global Variables | PS usa mecanismo nativo do CAppDialog |
| **Layout/info** | 9/10 — resultados no painel | 6/10 — resultados so no chart | PS mostra $ no painel; LF so no overlay |
| **Estado global** | 8/10 — minimalista | 4/10 — 15+ variaveis | PS tem menos metadade estado |
| **Hotkeys** | 9/10 — 10+ hotkeys | 0/10 — nenhum | PS tem atalhos de teclado |
| **Manutenibilidade** | 8/10 — helpers, listas | 6/10 — hardcoded inline | PS usa helpers de criacao |

### Conclusao Principal

O **Position Sizer e superior em drag & drop** porque **delega ao CAppDialog** em vez de reimplementar o que a biblioteca padrao ja faz. O LotForge tenta controlar demais o processo de drag com polling manual, flags globais e dois sistemas de drag coexistindo — criando overhead desnecessario e oportunidades para inconsistencias.

A melhoria de maior impacto seria: **eliminar o polling de drag do painel** e **remover o overlay bar drag**, deixando o drag de linhas 100% nativo via `CHARTEVENT_OBJECT_DRAG`. Isso eliminaria ~50% do codigo do OnChartEvent e reduziria o overhead por frame de ~200+ chamadas de API para ~2.
