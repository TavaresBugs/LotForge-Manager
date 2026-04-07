# Checklist Da Sessao Atual

Data: 2026-04-07
Escopo: menu do LotForge, comparacao mecanica com Position Sizer, limpeza de caches visuais, conclusao da Fase 2 e implementacao da Fase 3.

## Objetivo Da Sessao

- [x] Analisar como o Position Sizer plota e atualiza o menu.
- [x] Confirmar se o painel atual do LotForge usa painel externo ou `CAppDialog`.
- [x] Aproximar a mecanica do menu do LotForge do Position Sizer sem copiar o visual.
- [x] Remover caches/atalhos que podiam afetar a fidelidade do plot visual.
- [x] Concluir a Fase 1 do roadmap: isolamento do menu via dispatcher.
- [x] Concluir a Fase 2 do roadmap: ciclo visual do painel.
- [x] Implementar a Fase 3 do roadmap: silenciar trabalho de fundo durante interacao UI.

## Analise Concluida

- [x] Confirmado que o `Position Sizer` usa `CAppDialog` para o painel.
- [x] Confirmado que o drag do painel no `Position Sizer` e nativo do framework, nao manual.
- [x] Confirmado que o `Position Sizer` ainda usa `CHARTEVENT_MOUSE_MOVE`, mas nao para mover o painel.
- [x] Confirmado que o `Position Sizer` lembra a posicao do painel no fim do drag.
- [x] Confirmado que o `Position Sizer` usa helper de z-order (`HideShowMaximize()`).
- [x] Confirmado que o `LotForge` nao usa painel externo no menu atual.
- [x] Confirmado que o que fica fora do painel no `LotForge` sao apenas os objetos de preview no chart.

## Modificacoes Aplicadas Nesta Sessao

### 1. Mecanica Do Drag Do Painel

- [x] Declarados hooks nativos `OnDialogDragStart()` e `OnDialogDragEnd()` no `CLotForgePanel`.
- [x] Passado o estado `g_panel_dragging` para ser controlado pelos hooks nativos do `CDialog`.
- [x] Removido o polling manual de `Left()/Top()` no `OnChartEvent` para detectar drag do painel.
- [x] Removidas as variaveis `g_panel_last_x` e `g_panel_last_y`.
- [x] Mantido o bloqueio de trabalho pesado durante drag do painel.

### 1B. Fase 2 - Ciclo Visual Do Painel

- [x] Criado `RememberPanelState()` no `CLotForgePanel`.
- [x] Criado `BringPanelToFront()` no `CLotForgePanel`.
- [x] `OnDialogDragEnd()` passou a sincronizar o estado do painel por helper unico.
- [x] `OnClickCaption()` passou a poder trazer o painel para frente.
- [x] `OnClickButtonMinMax()` passou a reempilhar o painel apos minimizar/maximizar.
- [x] `Minimize()` foi sobrescrito para preservar a posicao atual do painel no estado minimizado.
- [x] `Maximize()` foi sobrescrito para restaurar a geometria normal na posicao lembrada.
- [x] `g_state.minimized` passou a ser sincronizado no proprio ciclo do dialog.
- [x] `g_state.panel_x` e `g_state.panel_y` passaram a ser sincronizados no proprio ciclo do dialog.

### 2. Limpeza De Cache / Plot Visual

- [x] Removido o tick-throttle de preview baseado em `entry/sl/tp`.
- [x] Removida a invalidacao manual desse cache em `HandleOrderSelection()`.
- [x] Removido o fast-path de overlay que reaproveitava texto/medidas em `UpdateOverlayPreviewLabel()`.
- [x] O overlay agora recalcula layout e fonte sempre com base na geometria atual do chart.
- [x] `UpdatePreview()` passou a aceitar `do_redraw` para separar repaint de logica.
- [x] `AdjustLots()` deixou de chamar `RefreshValues()` e `ChartRedraw()` por dentro.
- [x] `AdjustEntry()` deixou de chamar `RefreshValues()` e `ChartRedraw()` por dentro.

### 3. Inicio Da Fase 1 - Dispatcher Do Menu

- [x] Criado `UiDispatchCommand`.
- [x] Criado `UiDispatchState`.
- [x] Criado estado global `g_ui`.
- [x] Criados helpers `QueueUiRefresh()`, `QueueUiCommand()` e `QueueUiOrderSelection()`.
- [x] Criado `ProcessUiDispatch()`.
- [x] Criado `ProcessUiCancel()`.
- [x] Criado `ProcessUiSend()`.
- [x] Criado `ProcessUiManualBreakEven()`.
- [x] Criado `ProcessUiManualTrailing()`.
- [x] Criado `ProcessUiToggleAutoBE()`.
- [x] Criado `ProcessUiToggleAutoTrailing()`.
- [x] Criado `ProcessUiToggleAlgoTrading()`.
- [x] `OnChartEvent()` passou a chamar `ProcessUiDispatch()` imediatamente apos `g_panel.ChartEvent(...)`.

### 4. Desacoplamento Dos Handlers Do Painel

- [x] `OnClickRiskMode()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickPrimaryUp()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickPrimaryDn()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickEntryUp()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickEntryDn()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickTPUp()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickTPDn()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickSLUp()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickSLDn()` passou a apenas alterar estado e enfileirar refresh.
- [x] `OnClickCancel()` deixou de cancelar direto e passou a enfileirar `UI_CMD_CANCEL`.
- [x] `OnClickSend()` deixou de executar envio direto e passou a enfileirar `UI_CMD_SEND`.
- [x] `OnClickBE()` deixou de executar BE direto e passou a enfileirar `UI_CMD_MANUAL_BE`.
- [x] `OnClickTrailing()` deixou de executar trailing direto e passou a enfileirar `UI_CMD_MANUAL_TRAILING`.
- [x] `OnClickAutoBE()` deixou de alternar direto e passou a enfileirar `UI_CMD_TOGGLE_AUTO_BE`.
- [x] `OnClickAutoTrailing()` deixou de alternar direto e passou a enfileirar `UI_CMD_TOGGLE_AUTO_TRAILING`.
- [x] `OnClickAlgoTrading()` deixou de alternar direto e passou a enfileirar `UI_CMD_TOGGLE_ALGO_TRADING`.
- [x] `OnEndEditPrimary()` passou a apenas atualizar estado e enfileirar refresh.
- [x] `OnEndEditEntry()` passou a apenas atualizar estado e enfileirar refresh.
- [x] `OnEndEditTP()` passou a apenas atualizar estado e enfileirar refresh.
- [x] `OnEndEditSL()` passou a apenas atualizar estado e enfileirar refresh.
- [x] `HandleOrderSelection()` virou apenas enfileiramento de selecao.

### 5. Separacao Entre Trading E Repaint

- [x] `SendSelectedOrder()` continua dono do trade, mas nao mais do ciclo visual do menu.
- [x] `ClearTradeDraftAfterSuccessfulSend()` deixou de atualizar painel, apagar preview e redesenhar diretamente.
- [x] O redraw final agora pode ser centralizado no dispatcher para os eventos do menu.

### 6. Fase 3 - Interacao UI

- [x] Criada a flag global `g_ui_interaction_active`.
- [x] Criado `SyncUiInteractionState()` para derivar o estado de interacao UI.
- [x] Criado `ShouldPauseUiHeavyRefresh()` para centralizar o gate de trabalho visual pesado.
- [x] Criado `TrackUiInteractionEvent()` para observar clique/drag bruto do chart antes do dispatcher.
- [x] Criados `BeginActiveEdit()` e `EndActiveEdit()` no `CLotForgePanel`.
- [x] Criados `ResolveEditTarget()` e `OwnsObject()` no `CLotForgePanel`.
- [x] O edit ativo agora atualiza `g_state.edit_in_progress` e `g_state.editing_object`.
- [x] O drag nativo do painel agora sincroniza tambem a flag global de interacao UI.
- [x] `OnTick()` passou a respeitar `g_ui_interaction_active` para pular preview pesado.
- [x] `OnTimer()` passou a respeitar `g_ui_interaction_active` para pular preview pesado.
- [x] `CHARTEVENT_CHART_CHANGE` passou a respeitar `g_ui_interaction_active` para pular rebuild visual pesado.
- [x] O refresh visual dos markers de posicao aberta passou a ser pausado durante interacao UI.
- [x] `QueueUiRefresh()`, `QueueUiCommand()` e `QueueUiOrderSelection()` agora encerram edit ativo antes do dispatch.

## Arquivos Alterados Nesta Sessao

- [x] `LotForge_Manager.mq5`
- [x] `LotForge/Panel.mqh`
- [x] `LotForge/Preview.mqh`
- [x] `LotForge/Trading.mqh`
- [x] `docs/checklist-sessao-atual-menu-position-sizer.md`
- [x] `docs/menu-performance-roadmap.md`

## Fases Impactadas

- [x] Fase 1: concluida estruturalmente e validada em teste manual da sessao.
- [x] Fase 2: concluida no codigo e validada manualmente na sessao.
- [x] Fase 3: implementada no codigo para drag do painel e edit ativo dos campos.
- [x] 3.4 / 3.5: alteradas no preview para remover cache visual e separar redraw de logica.
- [ ] Fase 4: nao foi foco principal desta sessao.
- [ ] Fase 5: nao foi foco principal desta sessao.
- [ ] Fase 6: nao foi foco principal desta sessao.

## O Que Nao Foi Feito Nesta Sessao

- [ ] Nao foi feito redesign visual do menu.
- [ ] Nao foi reescrita a mecanica de handles/overlays fora do necessario para o dispatcher e o plot.
- [ ] Nao foi implementada ainda a adaptacao especifica da Fase 3 para os handles/overlay drag.
- [ ] Nao foi atacado o modelo de risco/calculo da Fase 6.
- [ ] Nao foi implementado fast-path de mercado novo para performance; nesta sessao a prioridade foi fidelidade visual e desacoplamento do menu.

## Validacao Feita

- [x] Revisao estrutural do fluxo do `Position Sizer` e do `LotForge`.
- [x] Revisao de referencias no codigo para arrasto, redraw, preview e cache.
- [x] Validacao manual no MT5 do fluxo funcional da Fase 1 conforme teste da sessao.
- [x] Validacao manual no MT5 do ciclo visual principal da Fase 2 conforme teste da sessao.
- [x] Tentativa de compilacao via MetaEditor no ambiente Wine.

## Validacao Pendente

- [ ] Validar digitacao nos edits sem disputa visual com preview.
- [ ] Validar que `g_ui_interaction_active` entra e sai corretamente ao clicar em edit, botao e chart.
- [ ] Validar que `OnTick()` e `OnTimer()` deixam de competir com a digitacao.
- [ ] Validar que os markers visuais deixam de competir com a digitacao sem quebrar a gestao automatica.
- [ ] Validar troca de timeframe apos a Fase 3 para confirmar que o gate visual nao deixa estado preso.
- [ ] Validar a Fase 3 junto do preview ativo e do drag do painel no mesmo grafico.

## Limitacao Encontrada Na Sessao

- [x] A compilacao no MetaEditor do ambiente Wine nao fechou porque os `#include "LotForge\\*.mqh"` do workspace nao foram resolvidos por esse ambiente.
- [x] O bloqueio observado foi de ambiente de include do terminal Wine, nao uma conclusao final de falha logica do dispatcher.

## Proxima Acao Recomendada

- [ ] Validar manualmente no MT5 a Fase 3 com foco em digitacao, drag do painel e preview ativo.
- [ ] Medir quantos `ChartRedraw()` ainda restam em caminhos do menu apos o dispatcher.
- [ ] Revisar se ainda existe algum handler do ecossistema do menu com efeito colateral direto fora do dispatcher.
- [ ] Depois da validacao da Fase 3, decidir entre adaptacao dos handles ou instrumentacao da Fase 4.
