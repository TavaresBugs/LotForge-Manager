# Menu Performance Roadmap

## Objetivo

Aproximar o comportamento do menu do LotForge ao padrao do Position Sizer no que importa para responsividade:

- painel feito em `CAppDialog` / `CDialog`
- drag nativo do painel pelo framework
- menu desacoplado do preview e do trading
- um dono unico para `ChartRedraw()`
- zero trabalho pesado rodando enquanto o painel esta sendo arrastado

Escopo principal deste documento:

- menu/painel
- ciclo de eventos do `CAppDialog`
- acoplamento entre menu, preview e trading

Fora do escopo imediato:

- redesign visual
- mover menu para plots no chart
- reescrever handles/overlays nesta fase

---

## Fatos verificados no Position Sizer

### 1. O painel deles e `CAppDialog`

O `Position Sizer` cria o painel com `CAppDialog::Create(...)`.

Referencias:

- `Position Sizer/Position Sizer.mqh:478`
- `MQL5/Include/Controls/Dialog.mqh:393`

Conclusao:

- eles nao usam um painel custom externo ao framework
- o padrao correto para nos continua sendo `CAppDialog`

### 2. O drag do painel usa `mouse move`, mas internamente ao framework

O `CAppDialog` ativa `CHART_EVENT_MOUSE_MOVE` automaticamente na criacao:

- `MQL5/Include/Controls/Dialog.mqh:532`

O ciclo do drag do dialog e este:

- `CDialog::OnDialogDragStart()` cria o drag object interno
- `CDialog::OnDialogDragProcess()` chama `Move(x, y)`
- `CDialog::OnDialogDragEnd()` finaliza o ciclo

Referencias:

- `MQL5/Include/Controls/Dialog.mqh:324`
- `MQL5/Include/Controls/Dialog.mqh:357`
- `MQL5/Include/Controls/Dialog.mqh:373`

Conclusao importante:

- o Position Sizer **nao elimina** `mouse move` para o painel
- ele apenas **nao implementa drag manual proprio do painel**
- quem move o painel e o proprio `CDialog`

### 3. O EA do Position Sizer ainda trata `CHARTEVENT_MOUSE_MOVE`

No `OnChartEvent()` do Position Sizer ha logica em `CHARTEVENT_MOUSE_MOVE`:

- `Position Sizer/Position Sizer.mq5:684`

Esse trecho e usado para acompanhar interacao com linhas e estados auxiliares, nao para mover o painel manualmente.

Conclusao:

- a frase correta nao e "o Position Sizer nao usa mouse move"
- a frase correta e "o Position Sizer nao faz drag manual do painel fora do framework"

### 4. Persistencia de posicao do painel e formalizada

O Position Sizer guarda a posicao ao final do drag e usa essa memoria em `Minimize()` / `Maximize()`.

Referencias:

- `Position Sizer/Position Sizer.mq5:783`
- `Position Sizer/Position Sizer.mqh:65`
- `Position Sizer/Position Sizer.mqh:2083`
- `Position Sizer/Position Sizer.mqh:2095`

Conclusao:

- a responsividade nao vem so do drag nativo
- vem tambem de um ciclo visual consistente do painel

### 5. Eles ainda usam helper de z-order

O Position Sizer usa `HideShowMaximize()` para reempilhar o painel acima dos objetos do grafico quando necessario.

Referencia:

- `Position Sizer/Position Sizer.mqh:5943`

Conclusao:

- isso nao e ganho bruto de CPU
- isso e robustez visual e previsibilidade do painel

---

## Estado atual do LotForge

### EA principal

O EA principal ainda esta mais acoplado:

- handlers do menu ainda podem puxar preview e redraw em cascata
- `MOUSE_MOVE` ainda participa do ecossistema de overlays/handles
- `OnTick()` e `OnTimer()` continuam atualizando preview e markers

### Variante experimental `MenuPerf`

Na variante `MenuPerf`, os seguintes ganhos ja entraram:

- prefixes isolados para coexistir com o EA original
- hooks nativos de drag/min/max do `CAppDialog`
- remocao de grande parte dos `ChartRedraw()` redundantes do menu
- caminho de preview do menu com `UpdatePreview(false)` para deixar o redraw do clique com o framework

Arquivos:

- `LotForge_MenuPerf.mq5`
- `LotForge_MenuPerf/Panel.mqh`
- `LotForge_MenuPerf/Preview.mqh`
- `LotForge_MenuPerf/Trading.mqh`

### Metricas atuais

Contagem bruta de `ChartRedraw(`:

- projeto atual: `30`
- variante `MenuPerf`: `4`

Chamadas restantes na variante:

- `LotForge_MenuPerf.mq5:628`
- `LotForge_MenuPerf.mq5:740`
- `LotForge_MenuPerf.mq5:754`
- `LotForge_MenuPerf/Preview.mqh:578`

Leitura correta dessas metricas:

- o menu ja esta muito mais leve
- mas ainda nao esta 100% isolado do resto

---

## O que significa "chegar perto de 100%"

### Para o menu

Aceitaremos como "quase paridade com Position Sizer" quando:

1. o painel se move via `CAppDialog` sem logica manual paralela
2. nenhum handler do painel chama trading diretamente
3. nenhum handler do painel e dono de redraw
4. preview e status sao consumidos por um orquestrador central
5. durante drag do painel, nenhuma rotina pesada de preview roda
6. minimizar, maximizar e restaurar preservam a mesma posicao
7. o painel pode ser trazido ao topo de forma previsivel

### Para a experiencia total do EA

Mesmo com o menu perfeito, ainda faltara:

- overlays/handles
- preview por tick em market order
- markers de posicao aberta

Conclusao:

- 100% do menu e possivel aproximar bem
- 100% da sensacao do EA inteiro exige uma segunda fase fora do menu

---

## TODO Checklist — 100% do menu

### Base estrutural

- [x] manter o menu em `CAppDialog` / `CDialog`
- [x] usar drag nativo do framework, sem drag manual proprio do painel
- [x] isolar a variante experimental em `LotForge_MenuPerf`
- [x] usar prefixes proprios para coexistir com o EA original
- [x] implementar hooks nativos de `OnDialogDragStart()`, `OnDialogDragEnd()`, `Minimize()` e `Maximize()`
- [x] parar de inferir drag do painel comparando `Left()/Top()` em cada pixel

### Fluxo de eventos

- [x] alinhar o fluxo do painel ao padrao do Position Sizer com `g_panel.OnEvent(...)` no `OnChartEvent()`
- [x] filtrar `CHARTEVENT_CHART_CHANGE` fora do fluxo normal do painel
- [x] centralizar a ponte menu -> preview/trading num dispatcher unico
- [x] criar `UiDispatchState`
- [x] criar `ProcessUiDispatch()`

### Handlers do menu

- [x] tirar `UpdatePreview()` direto dos handlers de `+/-`, risk mode e end-edit
- [x] tirar `RefreshValues()` direto desses handlers
- [x] mover `Send` para o dispatcher
- [x] mover `Cancel` para o dispatcher
- [x] fazer `HandleOrderSelection()` virar mudanca de estado + flags
- [x] mover BE manual para o dispatcher
- [x] mover Trailing manual para o dispatcher
- [x] mover os toggles/check-buttons (`Auto BE`, `Auto Trailing`, `Algo Trading`) para o dispatcher

### Redraw

- [x] reduzir os `ChartRedraw()` diretos do menu
- [x] deixar preview acionado pelo menu rodar com `UpdatePreview(false)`
- [x] garantir um redraw manual central apos dispatch quando necessario
- [x] remover os redraws redundantes restantes de init
- [ ] revisar se algum redraw restante do menu ainda pode ser colapsado

### Estado visual do painel

- [x] lembrar posicao corrente do painel em memoria durante drag/min/max
- [x] manter consistencia basica de min/max com a posicao lembrada
- [x] adicionar helper estilo `HideShowMaximize()` para z-order
- [x] persistir posicao/minimizado fora do ciclo de chart change
- [x] revisar bring-to-front do painel em cenarios de sobreposicao

### Trabalho de fundo durante interacao UI

- [x] pular preview pesado durante drag do painel
- [x] pular trabalho pesado tambem durante edit ativo de campos
- [x] revisar `OnTick()` para nao competir com interacao do menu
- [x] revisar `OnTimer()` para nao competir com interacao do menu
- [x] pausar refresh visual de markers enquanto a UI estiver em interacao ativa

### Acabamento

- [ ] instrumentar contador de dispatches por clique
- [ ] instrumentar contador de redraws por evento
- [ ] validar manualmente drag, click repetido, end-edit, min/max e chart change
- [ ] decidir se alguns pseudo-labels podem virar `CLabel` sem alterar a estetica

### Fora do escopo do 100% do menu

- [ ] otimizar handles/overlays
- [ ] otimizar preview de market order por tick
- [ ] otimizar markers de posicao aberta

---

## Arquitetura alvo

### Regra central

O painel deve ser uma camada burra de interface.

Ele pode:

- capturar clique
- capturar fim de edicao
- mudar `g_state`
- marcar flags de trabalho pendente

Ele nao deve:

- chamar `SendSelectedOrder()`
- chamar validacao de trading diretamente
- decidir quando redesenhar o chart
- ser dono do pipeline do preview

### Estrutura desejada

#### 1. `PanelState`

Continua sendo o estado editavel do menu.

Exemplos:

- `lots`
- `entry_price`
- `sl_points`
- `tp_points`
- `action`
- `risk_mode`

#### 2. `UiDispatchState`

Nova struct de flags de trabalho.

Exemplo:

```mq5
struct UiDispatchState
{
   bool controls_dirty;
   bool action_buttons_dirty;
   bool be_trailing_dirty;
   bool preview_dirty;
   bool status_dirty;
   bool request_send;
   bool request_cancel;
};
```

#### 3. `ProcessUiDispatch()`

Funcao central, chamada fora do painel, responsavel por:

- refrescar controles
- refrescar estilos de botoes
- disparar preview
- executar send/cancel
- decidir se ha `ChartRedraw()`

#### 4. Dono unico do redraw

Meta:

- somente o orquestrador decide `ChartRedraw()`

Idealmente:

- `Panel` nao chama redraw
- `Preview` nao chama redraw quando acionado por UI
- `Trading` nao chama redraw por conta propria

---

## Roadmap faseado

## Fase 1 — Isolamento completo do menu

### Objetivo

Separar `CAppDialog` do preview e do trading.

### Tarefas

1. Criar `UiDispatchState` global.
2. Alterar todos os handlers do painel para apenas:
   - atualizar `g_state`
   - marcar flags em `g_ui`
3. Criar `ProcessUiDispatch()`.
4. Chamar `ProcessUiDispatch()` imediatamente apos `g_panel.ChartEvent(...)`.
5. Mover `SendSelectedOrder()` para fora do painel.
6. Mover cancel/reset para fora do painel.
7. Garantir no maximo um redraw por ciclo de dispatch.

### Critério de aceite

- click em qualquer botao do menu nao chama preview/trading diretamente do handler
- click em qualquer botao do menu termina com no maximo um redraw
- painel continua visualmente identico

## Fase 2 — Paridade do ciclo visual do painel

### Objetivo

Fechar a parte que o Position Sizer trata como estado proprio do dialog.

### Tarefas

1. Adicionar helper equivalente a `HideShowMaximize()`.
2. Trazer painel ao topo quando necessario:
   - apos certas mudancas estruturais
   - opcionalmente ao clicar na caption
3. Persistir `panel_x`, `panel_y` e `minimized` nao apenas em chart change:
   - fim do drag
   - minimize
   - maximize
4. Revisar se a persistencia vai para:
   - terminal global variables
   - arquivo simples

### Critério de aceite

- painel reaparece na mesma posicao ao minimizar/maximizar
- painel nao "some atras" de objetos do grafico em cenarios comuns

## Fase 3 — Silenciar trabalho de fundo durante interacao UI

### Objetivo

Fazer o resto do EA respeitar interacao do painel.

### Tarefas

1. Criar flag de interacao UI:
   - `g_ui_interaction_active`
2. Ativar essa flag em:
   - drag do painel
   - edicao ativa de campos
   - opcionalmente hover/press de controles criticos
3. Em `OnTick()` e `OnTimer()`, pular preview pesado quando `g_ui_interaction_active == true`.
4. Manter somente trabalho realmente necessario em background.

### Critério de aceite

- digitar em edit box nao gera disputa com preview
- arrastar painel nao sofre interferencia visual do preview

## Fase 4 — Menu-only finish

### Objetivo

Extrair o maximo do menu sem tocar ainda na mecanica dos handles.

### Tarefas

1. Remover redraws restantes de inicializacao quando redundantes.
2. Revisar se alguns controles hoje criados como `CButton` podem ser `CLabel` sem perder estetica nem UX.
3. Validar se o custo de criacao de controles e irrelevante frente ao custo de interacao.
4. Revisar feedback visual dos botoes:
   - manter o feedback transient de click do `CButton`
   - usar estado persistente apenas quando houver selecao semantica real
   - evitar "parecer selecionado" quando a intencao for apenas confirmar o click
5. Instrumentar:
   - contador de `UpdatePreview()`
   - contador de `ChartRedraw()`
   - contador de dispatches por click

### Critério de aceite

- drag do painel perceptivelmente suave com preview ligado
- clicks do menu sem "soluço" visual
- metrica estavel de no maximo 1 dispatch pesado por acao

## Fase 5 — Paridade da experiencia completa

### Objetivo

Atacar o gargalo principal que sobra fora do menu: preview de mercado e overlays.

Diretriz desta fase:

- nao reintroduzir cache visual que reaproveite geometria, texto, fonte ou posicoes previamente desenhadas se isso puder alterar a fidelidade do plot
- nao reintroduzir throttle visual baseado em ultimo `entry/sl/tp` desenhado
- qualquer otimizacao futura deve preservar o mesmo resultado visual do rebuild completo

### Tarefas

1. Revisar o preview de mercado sem fast-path visual:
   - manter rebuild fiel quando o preco corrente mudar
   - otimizar apenas o que nao altera o resultado final do plot
2. Quando a regra de negocio for "stop tecnico absoluto":
   - `entry` varia por tick
   - `SL/TP` permanecem como ancoras absolutas quando definidos tecnicamente
   - risco/reward recalcula em ritmo controlado
   - a semantica do plot deve continuar vindo do estado atual, nao de geometria reaproveitada
   - esta semantica esta explicitamente adiada ate blindarmos os visualizadores de handles
3. Separar geometria de calculo financeiro:
   - `BuildTradePlan()` e `ValidateTradeRequest()` nao devem rodar em todo tick so porque o bid/ask mudou
   - recalculo financeiro completo deve acontecer por invalidacao de input ou timer controlado
4. Revisar overlays e markers sem cache visual agressivo.
5. Reduzir custo do `HandleMouseMoveDrag()`.
6. Rever se overlay-bar drag continua valendo frente ao custo.

### Observacao

Essa fase ja nao e mais "menu only".

## Fase 6 — Calculo e modelo de risco

### Objetivo

Revisar se o custo de calculo esta bem estruturado e se o modelo pode ficar mais proximo da disciplina do Position Sizer sem puxar peso desnecessario para cada tick.

### Tarefas

1. Separar "calculo barato de geometria" de "calculo completo de risco":
   - geometria = entry/sl/tp e linhas
   - calculo completo = lote, risco, reward, validacao broker
2. Criar cache de invalidacao para calculo:
   - invalidar em mudanca de `action`
   - invalidar em mudanca de `lots` / `risk_mode` / `risk_percent`
   - invalidar em mudanca de `sl_points` / `tp_points`
   - invalidar em mudanca de simbolo / regras do broker
3. Revisar chamadas repetidas de:
   - `BuildTradePlan()`
   - `ValidateTradeRequest()`
   - `SymbolInfo*`
   - `AccountInfo*`
4. Avaliar cache de metadata do simbolo:
   - `tick_size`
   - `tick_value`
   - `volume_min/max/step`
   - `stops_level`
   - `freeze_level`
5. Comparar precisao versus custo com o Position Sizer:
   - o PS centraliza calculo em `CalculateSettingsBasedOnLines()` + `CalculateRiskAndPositionSize()`
   - o alvo nao e copiar toda a complexidade dele
   - o alvo e copiar a disciplina: um caminho central de calculo, sem duplicacao e sem recalculo pesado desnecessario

### Critério de aceite

- variacao de bid/ask nao dispara validacao completa do plano em todo tick
- preview financeiro so recalcula quando um input realmente relevante muda
- custo aritmetico deixa de ser acoplado ao repaint do preview

---

## O que ainda falta para termos paridade real

### Gap 1. `OnTick()` e `OnTimer()` ainda pertencem ao mesmo ecossistema visual

O painel ja esta em `state + flags + dispatcher`, mas o trabalho de fundo ainda pode competir com edicao ativa e outras interacoes UI.

### Gap 2. Ainda ha pouco espaco para colapsar redraw residual

O menu caiu para `4` chamadas diretas de `ChartRedraw(`, mas ainda vale revisar se alguma das restantes pode desaparecer sem risco visual.

### Gap 3. Preview de mercado ainda usa rebuild completo demais

Hoje o custo maior remanescente nao esta nos botoes do menu, e sim no caminho que mistura tick -> preview -> overlays -> calculo.

### Gap 4. `MOUSE_MOVE` nao pode ser removido enquanto o painel for `CAppDialog`

Este e um ponto fechado pela analise do framework:

- `CAppDialog` precisa de `EventMouseMove()`
- logo, o objetivo nao e desligar `mouse move`
- o objetivo e manter o caminho de `mouse move` barato

---

## O que eu preciso para executar este roadmap

### Decisoes tecnicas

1. Confirmar que a `MenuPerf` sera a branch experimental oficial.
2. Confirmar que a Fase 1 pode mexer na arquitetura do fluxo de eventos do menu.
3. Confirmar que o objetivo imediato continua sendo:
   - menu primeiro
   - handles depois
4. Regra adiada para ordens a mercado:
   - `entry` varia por tick
   - `SL/TP` tecnicos ficam absolutos
   - nao implementar isso antes de proteger os visualizadores de handles

### Validacao manual no MT5

Precisaremos testar pelo menos estes cenarios:

1. drag do painel com preview ativo
2. clicks repetidos em `+/-`
3. digitar em campos de edit
4. minimizar/maximizar e restaurar
5. troca de timeframe
6. painel sobreposto a objetos do chart
7. ordem a mercado com ticks rapidos e preview ativo

### Criterio final de aprovacao

Eu sugiro aprovar a fase menu quando estes sintomas desaparecerem:

- stutter ao arrastar painel
- click de botao causando mais de um repintado perceptivel
- conflito entre digitar no painel e refresh do preview
- painel perdendo consistencia de posicao

---

## Ordem recomendada de execucao

1. Fase 1: isolamento completo do menu
2. Fase 2: paridade do ciclo visual do painel
3. Fase 3: silenciar trabalho de fundo durante interacao UI
4. Fase 4: finish do menu
5. Fase 5: market preview fast-path
6. Fase 6: calculo e risco
7. depois: handles/overlays finos

Essa ordem maximiza retorno com risco baixo.

---

## Resumo executivo

O caminho para chegar muito perto do Position Sizer nao e:

- trocar `CAppDialog`
- mover menu para objetos do chart
- eliminar `mouse move` do painel

O caminho certo e:

- deixar o `CAppDialog` fazer o drag nativo
- tirar preview/trading/redraw de dentro dos handlers do menu
- centralizar o commit do estado da UI
- reduzir o custo do que acontece ao redor do painel

Em termos praticos:

- a `MenuPerf` ja fechou o isolamento do menu e a paridade basica do ciclo visual do painel
- a proxima etapa critica e silenciar melhor `OnTick()` e `OnTimer()` durante interacao UI
- depois disso, o maior ganho vira de fast-path de mercado e desacoplamento entre calculo e repaint

---

## TODO Antes De Executar

Este bloco deve ser atualizado sempre antes de qualquer nova fase de implementacao.

### Baseline atual

- `MenuPerf` compila com `0 errors, 0 warnings`
- chamadas diretas de `ChartRedraw(` na `MenuPerf`: `4`
- Fase 1: concluida
- Fase 2: concluida e validada manualmente na sessao
- Fase 3: implementada em codigo, pendente de validacao manual no MT5
- Fase 4: implementada parcialmente em modo seguro, pendente de validacao manual no MT5
- Fase 5A: fast-path geometrico de mercado descartado quando afetar fidelidade visual do plot
- Adaptacao da Fase 3 aos handles: pendente

### TODO imediato — Fase 3

- [x] criar `g_ui_interaction_active`
- [x] ativar essa flag em drag do painel
- [x] ativar essa flag em edit ativo dos campos
- [x] fazer `OnTick()` respeitar essa flag
- [x] fazer `OnTimer()` respeitar essa flag
- [x] fazer `CHARTEVENT_CHART_CHANGE` respeitar essa flag no caminho visual pesado
- [x] pausar refresh visual de markers durante interacao UI
- [ ] medir se o preview deixa de competir com digitacao e drag

### TODO seguinte — Fase 4

- [] revisar feedback visual dos botoes para ficar mais proximo do comportamento transient do `Trade Bro`
- [] estender o mesmo feedback visual para `BE`, `Trailing` e toggles do painel
- [ ] validar se existe algum pseudo-botao que pode virar `CLabel`
- [] instrumentar contador de `UpdatePreview()`
- [] instrumentar contador de `ChartRedraw()`
- [] instrumentar contador de dispatches por clique
- [ ] validar no MT5 se o novo feedback visual continua claro sem parecer "travado"

### TODO seguinte — Adaptacao da Fase 3 aos handles

- [] criar estado proprio de interacao de handles sem mexer na semantica do drag
- [] usar esse estado apenas para silenciar trabalho concorrente ao redor do handle
- [] pausar `OnTick()` pesado durante interacao de handle
- [] pausar `OnTimer()` pesado durante interacao de handle
- [] pausar `CHART_CHANGE` pesado durante interacao de handle
- [] nao alterar `HandleNativeLineDrag()` nem a logica de precos dos handles nesta etapa
- [ ] validar que o drag continua identico e apenas o entorno fica mais leve

### TODO imediato — Micro-otimizacoes seguras dos handles

- [] nao reintroduzir `g_last_preview_*` nem qualquer cache equivalente no caminho visual dos handles
- [] trocar `RefreshValues()` por refresh parcial so de `Entry/SL/TP` no caminho do handle
- [] manter a mecanica do drag e a semantica dos handles intactas
- [ ] validar no MT5 se o drag continua identico e se o tick seguinte deixou de fazer rebuild redundante
