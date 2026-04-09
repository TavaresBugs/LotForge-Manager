//+------------------------------------------------------------------+
//|  ██  TradeParams e PanelState — implementações                   |
//+------------------------------------------------------------------+

void TradeParams::Clear()
  {
   entry_price  = 0.0; sl_price    = 0.0; tp_price    = 0.0;
   sl_points    = 0.0; tp_points   = 0.0; lots        = 0.0;
   risk_pct     = 0.0; risk_money  = 0.0; reward_money= 0.0; reward_pct = 0.0; rr_ratio = 0.0;
  }

bool TradeParams::IsValid() const { return (entry_price > 0.0 && lots > 0.0); }

void PreviewSnapshot::Clear()
  {
   visible            = false;
   action             = ACTION_NONE;
   is_buy             = false;
   entry_price        = 0.0;
   sl_price           = 0.0;
   tp_price           = 0.0;
   plan_valid         = false;
   plan_lots          = 0.0;
   risk_money         = 0.0;
   reward_money       = 0.0;
   risk_pct           = 0.0;
   reward_pct         = 0.0;
   effective_label    = "";
   short_label        = "";
   entry_line_tooltip = "";
   sl_line_tooltip    = "";
   tp_line_tooltip    = "";
   en_label           = "";
   sl_label           = "";
   tp_label           = "";
  }

void PanelState::Init()
  {
   panel_x     = InpPanelX;
   panel_y     = InpPanelY;
   minimized   = false;
   action      = ACTION_NONE;
   active_edit = EDIT_TARGET_NONE;
   lots        = InpDefaultLots;
   entry_price = 0.0;
   sl_points   = MathMax(0.0, MathRound(InpDefaultSlPoints));
   tp_points   = MathMax(0.0, MathRound(InpDefaultTpPoints));
   market_sl_price = 0.0;
   market_tp_price = 0.0;
   order_comment      = "";
   risk_mode          = InpRiskMode;
   risk_percent       = InpRiskPercent;
   entry_line_visible = false;
   sl_line_visible    = false;
   tp_line_visible    = false;
   rr_zone_visible    = InpShowRRZone;
   break_even_enabled    = false;
   break_even_points     = 0;
   trailing_stop_enabled = false;
   trailing_stop_points  = 0;
   algo_trading_ui_enabled = false;
   preview_busy       = false;
   syncing            = false;
   edit_in_progress   = false;
   editing_object     = EDIT_TARGET_NONE;
   status_text        = "";
  }

void PanelState::Reset() { Init(); }


//+------------------------------------------------------------------+
//|  ██  GESTÃO DE POSIÇÃO — HELPERS E PIPELINE                      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  FindManagedIndex — retorna índice do ticket no array interno     |
//|  Retorna -1 se não encontrado.                                    |
//+------------------------------------------------------------------+

int FindManagedIndex(const ulong ticket)
  {
   int n = ArraySize(g_managed_trades);
   for(int i = 0; i < n; i++)
      if(g_managed_trades[i].ticket == ticket)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//|  EnsureManagedState — cria entrada de estado se ainda não existe  |
//|  Captura risco original na primeira chamada para o ticket.        |
//+------------------------------------------------------------------+

void EnsureManagedState(const ulong ticket)
  {
   if(FindManagedIndex(ticket) >= 0) return;   // já existe

   if(!PositionSelectByTicket(ticket)) return;

   ManagedTradeState ms;
   ms.ticket             = ticket;
   ms.symbol             = PositionGetString(POSITION_SYMBOL);
   ms.initial_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   ms.initial_sl         = PositionGetDouble(POSITION_SL);
   ms.initial_tp         = PositionGetDouble(POSITION_TP);
   ms.initial_risk_points = (ms.initial_sl > 0.0)
                            ? MathAbs(ms.initial_open_price - ms.initial_sl) / _Point
                            : 0.0;
   ms.be_applied         = false;
   ms.partial_done       = false;
   ms.trailing_armed     = false;
   ms.algo_managed       = false;

   int n = ArraySize(g_managed_trades);
   ArrayResize(g_managed_trades, n + 1);
   g_managed_trades[n] = ms;
  }

//+------------------------------------------------------------------+
//|  SyncManagedTradeState — sincroniza array com posições abertas   |
//|  Cria entradas para novas posições. Limpa entradas encerradas.   |
//+------------------------------------------------------------------+

void SyncManagedTradeState()
  {
   // ── 1. Criar entradas para posições abertas do símbolo + magic ───
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicNumber && magic != 0) continue;
      EnsureManagedState(t);
      // Se Algo Trading ligado ao abrir posição, marcar como algo_managed
      if(g_algo_trading_enabled)
        {
         int idx = FindManagedIndex(t);
         if(idx >= 0 && !g_managed_trades[idx].algo_managed)
           {
            g_managed_trades[idx].algo_managed   = true;
            g_managed_trades[idx].trailing_armed = true;
           }
        }
     }

   // ── 2. Limpar entradas de posições já encerradas ──────────────────
   int n = ArraySize(g_managed_trades);
   for(int i = n - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(g_managed_trades[i].ticket))
        {
         // Apagar markers visuais antes de remover entrada
         EraseManagedTradeMarkers(g_managed_trades[i].ticket);
         // Remover entrada: shift para baixo
         for(int j = i; j < n - 1; j++)
            g_managed_trades[j] = g_managed_trades[j + 1];
         n--;
         ArrayResize(g_managed_trades, n);
        }
     }
  }

//+------------------------------------------------------------------+
//|  IsPositionProtected — SL está do lado seguro (além da entrada)   |
//|  Verifica se o stop já protege a entrada (BE ou melhor).          |
//+------------------------------------------------------------------+

bool IsPositionProtected(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   long   type  = PositionGetInteger(POSITION_TYPE);
   if(sl == 0.0) return false;
   if(type == POSITION_TYPE_BUY)  return (sl >= open);
   if(type == POSITION_TYPE_SELL) return (sl <= open);
   return false;
  }

//+------------------------------------------------------------------+
//|  SyncProtectionState — sincroniza be_applied com o SL real       |
//|  Se a posição já estiver protegida no broker, marca be_applied.  |
//|  Chamado antes de qualquer decisão de BE/trailing para evitar    |
//|  loop de reaplicação quando BE já existe externamente.           |
//+------------------------------------------------------------------+

void SyncProtectionState(const int idx)
  {
   if(idx < 0) return;
   if(g_managed_trades[idx].be_applied) return;   // já sincronizado — sair rápido
   if(IsPositionProtected(g_managed_trades[idx].ticket))
      g_managed_trades[idx].be_applied = true;
  }

//+------------------------------------------------------------------+
//|  PositionProgressToTargetPct — % do caminho percorrido até o TP  |
//+------------------------------------------------------------------+

double PositionProgressToTargetPct(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return 0.0;
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double tp    = PositionGetDouble(POSITION_TP);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   long   type  = PositionGetInteger(POSITION_TYPE);
   if(tp == 0.0) return 0.0;
   double total_dist = MathAbs(tp - open);
   if(total_dist <= 0.0) return 0.0;
   double dist_done = (type == POSITION_TYPE_BUY) ? (price - open) : (open - price);
   double pct = (dist_done / total_dist) * 100.0;
   return MathMax(0.0, pct);
  }

//+------------------------------------------------------------------+
//|  TryManualBreakEven — aplica BE imediatamente na posição         |
//|  Move SL para open + offset de proteção.                         |
//|  Não piora stop já protegido.                                    |
//+------------------------------------------------------------------+

bool TryManualBreakEven(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   long   type = PositionGetInteger(POSITION_TYPE);

   double offset = InpBEProtectOffsetPts * _Point;
   double new_sl;
   if(type == POSITION_TYPE_BUY)
      new_sl = NormalizeDouble(open + offset, _Digits);
   else
      new_sl = NormalizeDouble(open - offset, _Digits);

   // ── Verificar se já está protegido igual ou melhor ────────────────
   if(type == POSITION_TYPE_BUY  && sl > 0.0 && sl >= new_sl)
     {
      // Sincronizar flag interno e sair sem modificação e sem loop
      EnsureManagedState(ticket);
      int idx = FindManagedIndex(ticket);
      if(idx >= 0) g_managed_trades[idx].be_applied = true;
      SetStatus(StringFormat("Posição #%d já protegida (SL=%.5f ≥ BE=%.5f).", ticket, sl, new_sl), true);
      return true;
     }
   if(type == POSITION_TYPE_SELL && sl > 0.0 && sl <= new_sl)
     {
      EnsureManagedState(ticket);
      int idx = FindManagedIndex(ticket);
      if(idx >= 0) g_managed_trades[idx].be_applied = true;
      SetStatus(StringFormat("Posição #%d já protegida (SL=%.5f ≤ BE=%.5f).", ticket, sl, new_sl), true);
      return true;
     }

   // ── Verificar stop level mínimo do broker ────────────────────────
   int stop_lvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   double current_price = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   double min_dist = stop_lvl * _Point;
   if(MathAbs(current_price - new_sl) < min_dist)
     {
      // Ajustar para respeitar stop level
      if(type == POSITION_TYPE_BUY)
         new_sl = NormalizeDouble(current_price - min_dist - _Point, _Digits);
      else
         new_sl = NormalizeDouble(current_price + min_dist + _Point, _Digits);
     }

   if(g_trade.PositionModify(ticket, new_sl, tp))
     {
      // Verificar se o resultado final realmente protege a entrada
      // (o broker pode ter ajustado o SL para cumprir stop level)
      bool really_protected = IsPositionProtected(ticket);
      EnsureManagedState(ticket);
      int idx = FindManagedIndex(ticket);
      if(idx >= 0) g_managed_trades[idx].be_applied = really_protected;
      SetStatus(StringFormat("BE aplicado — #%d SL movido para %.5f.", ticket, new_sl), true);
      Print("[BE Manual] ticket=", ticket, " new_sl=", new_sl, " protected=", really_protected);
      return true;
     }
   else
     {
      SetStatus(StringFormat("Falha ao aplicar BE #%d — erro %d.", ticket, GetLastError()), true);
      Print("[BE Manual] ERRO ticket=", ticket, " err=", GetLastError());
      return false;
     }
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  TryAutoBreakEven — aplica BE quando posição atinge % do alvo    |
//|  Gatilho: PositionProgressToTargetPct >= InpBETriggerTargetPct   |
//|  Sem TP definido: auto BE não dispara (não inventa alvo).        |
//|  Sem loop: SyncProtectionState garante saída rápida se já prot.  |
//+------------------------------------------------------------------+

bool TryAutoBreakEven(const ulong ticket)
  {
   int idx = FindManagedIndex(ticket);
   if(idx < 0) return false;

   // Sincronizar proteção real antes de qualquer decisão — previne loop
   SyncProtectionState(idx);

   if(g_managed_trades[idx].be_applied) return false;   // já protegido (real ou flag)

   // Validar input do usuário — faixa segura [1, 100]
   double trigger_pct = MathMax(1.0, MathMin(100.0, InpBETriggerTargetPct));

   // Sem TP: não é possível calcular progresso — não disparar auto BE
   // (usuário pode usar BE manual; não inventar alvo alternativo)
   if(!PositionSelectByTicket(ticket)) return false;
   if(PositionGetDouble(POSITION_TP) == 0.0) return false;

   // Verificar se atingiu o percentual configurado do alvo
   double pct = PositionProgressToTargetPct(ticket);
   if(pct < trigger_pct) return false;   // ainda abaixo do gatilho — sair silenciosamente

   // Atingiu o gatilho — aplicar BE
   return TryManualBreakEven(ticket);
  }

//+------------------------------------------------------------------+
//|  TryPartialClose — fecha parcialmente se progresso >= gatilho    |
//|  Executa no máximo uma vez por posição (partial_done).           |
//+------------------------------------------------------------------+

bool TryPartialClose(const ulong ticket)
  {
   int idx = FindManagedIndex(ticket);
   if(idx < 0) return false;
   if(g_managed_trades[idx].partial_done) return false;

   if(!PositionSelectByTicket(ticket)) return false;
   double tp = PositionGetDouble(POSITION_TP);
   if(tp == 0.0) return false;   // sem TP — não inventar alvo

   double pct = PositionProgressToTargetPct(ticket);
   if(pct < InpAlgoPartialTrigger) return false;

   double lote      = PositionGetDouble(POSITION_VOLUME);
   double lote_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lote_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lote_step <= 0.0) lote_step = 0.01;

   double lote_fechar = MathFloor((lote * InpAlgoPartialClosePct / 100.0) / lote_step) * lote_step;
   if(lote_fechar < lote_min)  lote_fechar = lote_min;
   if(lote_fechar >= lote)     lote_fechar = lote_min;   // nunca fechar tudo pelo parcial

   if(lote_fechar < lote_min || lote_fechar >= lote)
     {
      Print("[Parcial] #", ticket, " lote insuficiente para fechar parcialmente (", lote, " lots).");
      g_managed_trades[idx].partial_done = true;   // marcar para não tentar novamente
      return false;
     }

   if(g_trade.PositionClosePartial(ticket, lote_fechar))
     {
      g_managed_trades[idx].partial_done = true;
      string msg = StringFormat("Parcial #%d: %.2f lotes fechados @ %.0f%% do TP.", ticket, lote_fechar, pct);
      SetStatus(msg, true);
      Print("[Parcial] ", msg);
      return true;
     }
   else
     {
      int err = GetLastError();
      Print("[Parcial] ERRO ao fechar parcialmente #", ticket, " err=", err);
      SetStatus(StringFormat("Erro no fechamento parcial #%d — cód. %d. BE/Trailing mantidos.", ticket, err), true);
      // Marcar como feito para não re-tentar em loop; BE e trailing continuam
      g_managed_trades[idx].partial_done = true;
      return false;
     }
  }

//+------------------------------------------------------------------+
//|  TryTrailingStop — avança trailing se condições forem atendidas  |
//|  Nunca piora o stop. Só atua após BE se InpTrailingRequiresBE.   |
//+------------------------------------------------------------------+

bool TryTrailingStop(const ulong ticket)
  {
   int idx = FindManagedIndex(ticket);
   if(idx < 0) return false;
   if(!g_managed_trades[idx].trailing_armed) return false;

   // Sincronizar proteção real antes do gate — aceita BE manual não registrado
   SyncProtectionState(idx);

   // Gate: trailing só após proteção real (be_applied reflete estado real após sync)
   if(InpTrailingRequiresBE && !g_managed_trades[idx].be_applied)
     return false;

   if(!PositionSelectByTicket(ticket)) return false;
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   long   type  = PositionGetInteger(POSITION_TYPE);

   // Calcular distância do trailing: usar input ou risco inicial
   double dist_pts = (double)InpTrailingDistPts;
   if(dist_pts <= 0.0)
      dist_pts = g_managed_trades[idx].initial_risk_points;
   if(dist_pts <= 0.0) return false;

   double dist = dist_pts * _Point;
   double new_sl;
   bool   should_move = false;

   if(type == POSITION_TYPE_BUY)
     {
      new_sl = NormalizeDouble(price - dist, _Digits);
      // Floor: nunca abaixo do SL atual (nunca piora proteção conquistada)
      double floor_sl = (sl > 0.0) ? sl : NormalizeDouble(open + InpBEProtectOffsetPts * _Point, _Digits);
      if(new_sl < floor_sl) new_sl = floor_sl;
      if(new_sl > sl + (2.0 * _Point))
         should_move = true;
     }
   else  // SELL
     {
      new_sl = NormalizeDouble(price + dist, _Digits);
      // Ceil: nunca acima do SL atual (nunca piora proteção conquistada)
      double ceil_sl = (sl > 0.0) ? sl : NormalizeDouble(open - InpBEProtectOffsetPts * _Point, _Digits);
      if(new_sl > ceil_sl) new_sl = ceil_sl;
      if(sl == 0.0 || new_sl < sl - (2.0 * _Point))
         should_move = true;
     }

   if(!should_move) return false;

   // Verificar stop level
   int stop_lvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   double cur_p = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   if(MathAbs(cur_p - new_sl) < stop_lvl * _Point) return false;

   if(g_trade.PositionModify(ticket, new_sl, tp))
     {
      Print("[Trailing] #", ticket, " SL -> ", new_sl);
      return true;
     }
   else
     {
      Print("[Trailing] ERRO #", ticket, " err=", GetLastError());
      return false;
     }
  }

//+------------------------------------------------------------------+
//|  RunAutomatedTradeManagement — pipeline completo no OnTick        |
//|  Ordem correta:                                                   |
//|    1. Sincronizar proteção real do ticket (SyncProtectionState)   |
//|    2. Auto BE (só age se não protegido ainda)                     |
//|    3. Trailing (só age se protegido)                              |
//|    4. Parcial (só no pipeline Algo, uma vez por ticket)           |
//+------------------------------------------------------------------+

void RunAutomatedTradeManagement()
  {
   bool auto_be_on    = g_state.break_even_enabled;
   bool auto_trail_on = g_state.trailing_stop_enabled;

   int n = ArraySize(g_managed_trades);
   for(int i = 0; i < n; i++)
     {
      ulong t = g_managed_trades[i].ticket;
      if(!PositionSelectByTicket(t)) continue;   // já fechada — SyncManagedTradeState vai limpar

      bool is_algo = g_managed_trades[i].algo_managed;

      // ── 1. Sincronizar proteção real — base para todas as decisões ─
      SyncProtectionState(i);

      // ── 2. Auto BE ────────────────────────────────────────────────
      if(auto_be_on || is_algo)
         TryAutoBreakEven(t);

      // ── 3. Trailing (aproveita be_applied já sincronizado) ────────
      if(auto_trail_on || is_algo)
         TryTrailingStop(t);

      // ── 4. Parcial (apenas Algo; nunca bloqueia BE/trailing) ──────
      if(is_algo)
         TryPartialClose(t);
     }
  }

//+------------------------------------------------------------------+
//|  ██  MANAGED TRADE MARKERS — Open position visual layer           |
//|                                                                   |
//|  Independent of preview/montage layer. Reads real position data   |
//|  from PositionSelectByTicket(). Own candle-based horizontal       |
//|  geometry: left = bar0-1, right = bar0+3 candles ahead.          |
//|  OBJ_RECTANGLE_LABEL + OBJ_LABEL with natural right-edge clip.   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  UpdateOpenTradeMarker — create/update a single floating handle   |
//|                                                                   |
//|  Candle-based horizontal geometry — independent of preview.       |
//|  · Left anchor  = 1 candle behind bar-0 (shift 1)                 |
//|  · Right anchor = 3 candles ahead of bar-0 into the future        |
//|  · Both converted to screen X via ChartTimePriceToXY              |
//|  · Y from price via ChartTimePriceToXY                            |
//|  · OBJ_RECTANGLE_LABEL + OBJ_LABEL in CORNER_LEFT_UPPER          |
//|  · No right-edge clamping — natural "eaten by scale" clipping     |
//+------------------------------------------------------------------+

void UpdateOpenTradeMarker(const string obj_id,
                           const string text,
                           const double price,
                           const bool   above_line,
                           const color  bg_clr,
                           const color  border_clr,
                           const color  txt_clr)
  {
   string bg_n  = MNGD_PFX + obj_id + "_bg";
   string txt_n = MNGD_PFX + obj_id + "_tx";

   // ── Compute candle pixel width from two real bars ─────────────────
   datetime t_bar0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime t_bar1 = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(t_bar0 == 0 || t_bar1 == 0)
     {
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
      return;
     }

   int px0, py0, px1, py1_scr;
   if(!ChartTimePriceToXY(0, 0, t_bar0, price, px0, py0) ||
      !ChartTimePriceToXY(0, 0, t_bar1, price, px1, py1_scr))
     {
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
      return;
     }

   int candle_px = MathAbs(px0 - px1);   // pixel width of 1 candle
   if(candle_px < 1) candle_px = 8;      // fallback

   // Scale-aware span: same candle count as preview handles
   // Starts 1 candle behind bar-0, extends PreviewCandleCount() candles forward
   int span_candles = PreviewCandleCount() + 1;   // +1 for the 1-back anchor
   int bar_x = px1 - 2;                           // start from bar-1 position
   int bar_w = candle_px * span_candles + 2;      // full scale-aware width
   if(bar_w < 1)
     {
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
      return;
     }

   int py = py0;

   // ── Vertical sanity: hide if off-screen ───────────────────────────
   int chart_h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(py < -OVL_BAR_H || py > chart_h + OVL_BAR_H)
     {
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
      return;
     }

   int box_h = OVL_BAR_H;
   int box_y;
   if(above_line)
      box_y = py - OVL_LINE_OFFSET - box_h;
   else
      box_y = py + OVL_LINE_OFFSET;

   ExpandOverlayBarToFitText(bar_x, bar_w, text);
   int avail_w  = MathMax(10, bar_w - 2 * OVL_PAD_X);
   string fitted_text = FitHandleLabelText(text, avail_w);

   uint tw = 0, th = 0;
   MeasureHandleLabelText(fitted_text == "" ? " " : fitted_text, tw, th);

   // ── Text position ─────────────────────────────────────────────────
   int txt_x_pos = bar_x + OVL_PAD_X;
   int txt_y_pos = box_y + MathMax(1, (OVL_BAR_H - (int)th) / 2 - 1);

   // ── OBJ_RECTANGLE_LABEL (background bar) ─────────────────────────
   if(ObjectFind(0, bg_n) < 0)
     {
      if(!ObjectCreate(0, bg_n, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, bg_n, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg_n, OBJPROP_HIDDEN,       false);
      ObjectSetInteger(0, bg_n, OBJPROP_BACK,         false);
      ObjectSetInteger(0, bg_n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg_n, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
     }
   ObjectSetInteger(0, bg_n, OBJPROP_XDISTANCE, bar_x);
   ObjectSetInteger(0, bg_n, OBJPROP_YDISTANCE, box_y);
   ObjectSetInteger(0, bg_n, OBJPROP_XSIZE,     bar_w);
   ObjectSetInteger(0, bg_n, OBJPROP_YSIZE,     box_h);
   ObjectSetInteger(0, bg_n, OBJPROP_BGCOLOR,   bg_clr);
   ObjectSetInteger(0, bg_n, OBJPROP_COLOR,     border_clr);

   // ── OBJ_LABEL (text inside the bar) ──────────────────────────────
   if(ObjectFind(0, txt_n) < 0)
     {
      if(!ObjectCreate(0, txt_n, OBJ_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, txt_n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, txt_n, OBJPROP_HIDDEN,     false);
      ObjectSetInteger(0, txt_n, OBJPROP_BACK,       false);
      ObjectSetInteger(0, txt_n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, txt_n, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
     }
   ApplyHandleLabelFont(txt_n);
   ObjectSetInteger(0, txt_n, OBJPROP_XDISTANCE, txt_x_pos);
   ObjectSetInteger(0, txt_n, OBJPROP_YDISTANCE, txt_y_pos);
   ObjectSetString(0,  txt_n, OBJPROP_TEXT,      fitted_text);
   ObjectSetInteger(0, txt_n, OBJPROP_COLOR,     txt_clr);
  }

//+------------------------------------------------------------------+
//|  EraseManagedTradeMarkers — remove all marker objects for ticket  |
//+------------------------------------------------------------------+

void EraseManagedTradeMarkers(const ulong ticket)
  {
   string pfx = MNGD_PFX + IntegerToString(ticket) + "_";
   string kinds[] = {"tp_bg", "tp_tx", "sl_bg", "sl_tx", "mid_bg", "mid_tx", "be_bg", "be_tx"};
   int cnt = ArraySize(kinds);
   for(int i = 0; i < cnt; i++)
     {
      string n = pfx + kinds[i];
      // Also try the simplified naming
      if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
     }
   // Fallback: delete by constructed prefix scan
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, pfx) == 0)
         ObjectDelete(0, n);
     }
  }

//+------------------------------------------------------------------+
//|  EraseAllManagedTradeMarkers — remove ALL managed marker objects  |
//+------------------------------------------------------------------+

void EraseAllManagedTradeMarkers()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, MNGD_PFX) == 0)
         ObjectDelete(0, n);
     }
  }

//+------------------------------------------------------------------+
//|  UpdateManagedTradeMarkers — draw TP/SL/Mid markers for ticket   |
//|  Reads real position data only — no dependency on g_state/preview|
//+------------------------------------------------------------------+

void UpdateManagedTradeMarkers(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return;

   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl         = PositionGetDouble(POSITION_SL);
   double tp         = PositionGetDouble(POSITION_TP);
   double volume     = PositionGetDouble(POSITION_VOLUME);
   long   pos_type   = PositionGetInteger(POSITION_TYPE);
   bool   is_buy     = (pos_type == POSITION_TYPE_BUY);

   string tk_str = IntegerToString(ticket);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);

   // ── TP marker ─────────────────────────────────────────────────────
   if(tp > 0.0)
     {
      double tp_money = 0.0;
      double tp_pct   = 0.0;
      string tp_reason;
      if(CalcNetRewardMoneyForMove(open_price, tp, volume, is_buy, tp_money, tp_reason))
        {
         tp_money = NormalizeDouble(tp_money, 2);
         if(balance > 0.0)
            tp_pct = NormalizeDouble(tp_money / balance * 100.0, 2);
        }
      string tp_text = StringFormat("TP %s | +$%.2f", FormatPrice(tp), tp_money);
      if(tp_pct > 0.0)
         tp_text += StringFormat(" | %.2f%%", tp_pct);

      bool tp_above = is_buy;
      UpdateOpenTradeMarker(tk_str + "_tp", tp_text, tp, tp_above,
                            CLR_OVL_HANDLE_BG, CLR_PREV_TP_BORDER, CLR_PREV_TP_TEXT);
     }
   else
     {
      string bg_n  = MNGD_PFX + tk_str + "_tp_bg";
      string txt_n = MNGD_PFX + tk_str + "_tp_tx";
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
     }

   // ── SL marker ─────────────────────────────────────────────────────
   if(sl > 0.0)
     {
      double sl_money = 0.0;
      double sl_pct   = 0.0;
      string sl_reason;
      if(CalcNetRiskMoneyForMove(open_price, sl, volume, is_buy, sl_money, sl_reason))
        {
         sl_money = NormalizeDouble(sl_money, 2);
         if(balance > 0.0)
            sl_pct = NormalizeDouble(sl_money / balance * 100.0, 2);
        }
      string sl_text = StringFormat("SL %s | -$%.2f", FormatPrice(sl), sl_money);
      if(sl_pct > 0.0)
         sl_text += StringFormat(" | %.2f%%", sl_pct);

      bool sl_above = !is_buy;
      UpdateOpenTradeMarker(tk_str + "_sl", sl_text, sl, sl_above,
                            CLR_OVL_HANDLE_BG, CLR_PREV_SL_BORDER, CLR_PREV_SL_TEXT);
     }
   else
     {
      string bg_n  = MNGD_PFX + tk_str + "_sl_bg";
      string txt_n = MNGD_PFX + tk_str + "_sl_tx";
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
     }

   // ── Mid-target / Partial marker ───────────────────────────────────
   int mgd_idx = FindManagedIndex(ticket);
   bool partial_already_done = (mgd_idx >= 0 && g_managed_trades[mgd_idx].partial_done);

   if(InpShowMidTargetBlock && tp > 0.0 && !partial_already_done)
     {
      double partial_pct = MathMax(1.0, MathMin(100.0, InpAlgoPartialTrigger));
      double mid_price;
      if(is_buy)
         mid_price = NormalizePriceValue(open_price + (tp - open_price) * partial_pct / 100.0);
      else
         mid_price = NormalizePriceValue(open_price - (open_price - tp) * partial_pct / 100.0);

      double mid_money = 0.0;
      string mid_reason;
      if(CalcNetRewardMoneyForMove(open_price, mid_price, volume, is_buy, mid_money, mid_reason))
         mid_money = NormalizeDouble(mid_money, 2);

      string mid_text = StringFormat("%.0f%% TP | %s | +$%.2f",
                                      partial_pct, FormatPrice(mid_price), mid_money);

      bool mid_above = is_buy;
      UpdateOpenTradeMarker(tk_str + "_mid", mid_text, mid_price, mid_above,
                            CLR_OVL_HANDLE_BG, C'120,140,180', C'40,60,120');
     }
   else
     {
      string bg_n  = MNGD_PFX + tk_str + "_mid_bg";
      string txt_n = MNGD_PFX + tk_str + "_mid_tx";
      if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
      if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
     }

   // ── BE marker ─────────────────────────────────────────────────────
   //  Shows only when position is truly protected (SL on profitable side).
   //  Reflects actual SL level — not necessarily open_price.
   bool show_be = false;
   double be_price = 0.0;
   if(mgd_idx >= 0 && g_managed_trades[mgd_idx].be_applied && sl > 0.0)
     {
      // Verify SL is actually on the profitable side
      if(is_buy && sl >= open_price)
        { show_be = true; be_price = sl; }
      else if(!is_buy && sl <= open_price)
        { show_be = true; be_price = sl; }
     }

   if(show_be)
     {
      double be_money = 0.0;
      double be_pct   = 0.0;
      string be_reason;
      if(CalcNetRewardMoneyForMove(open_price, be_price, volume, is_buy, be_money, be_reason))
        {
         be_money = NormalizeDouble(be_money, 2);
         if(balance > 0.0)
            be_pct = NormalizeDouble(be_money / balance * 100.0, 2);
        }
      string be_text;
      if(be_money > 0.001)
         be_text = StringFormat("BE %s | +$%.2f", FormatPrice(be_price), be_money);
      else
         be_text = StringFormat("BE %s", FormatPrice(be_price));
      if(be_pct > 0.001)
         be_text += StringFormat(" | +%.2f%%", be_pct);

      // BE sits on the entry side: BUY → above_line=false (below entry), SELL → above_line=true
      bool be_above = !is_buy;
      UpdateOpenTradeMarker(tk_str + "_be", be_text, be_price, be_above,
                            CLR_OVL_HANDLE_BG, CLR_BE_BORDER, C'140,90,0');
     }
   else
     {
      string bg_n2  = MNGD_PFX + tk_str + "_be_bg";
      string txt_n2 = MNGD_PFX + tk_str + "_be_tx";
      if(ObjectFind(0, bg_n2)  >= 0) ObjectDelete(0, bg_n2);
      if(ObjectFind(0, txt_n2) >= 0) ObjectDelete(0, txt_n2);
     }
  }

//+------------------------------------------------------------------+
//|  RefreshAllManagedTradeMarkers — called from OnTick after sync   |
//+------------------------------------------------------------------+

void RefreshAllManagedTradeMarkers()
  {
   // ── Build set of active tickets ───────────────────────────────────
   int n = ArraySize(g_managed_trades);
   for(int i = 0; i < n; i++)
     {
      ulong t = g_managed_trades[i].ticket;
      if(PositionSelectByTicket(t))
         UpdateManagedTradeMarkers(t);
      else
         EraseManagedTradeMarkers(t);
     }

   // ── Clean orphan marker objects (tickets no longer in array) ──────
   //  Only run occasionally to avoid overhead — simple scan
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string obj_n = ObjectName(0, i, 0, -1);
      if(StringFind(obj_n, MNGD_PFX) != 0) continue;
      // Extract ticket from name: MNGD_PFX + "ticket_kind_suffix"
      string remainder = StringSubstr(obj_n, StringLen(MNGD_PFX));
      int sep = StringFind(remainder, "_");
      if(sep <= 0) { ObjectDelete(0, obj_n); continue; }
      string tk_part = StringSubstr(remainder, 0, sep);
      ulong tk = (ulong)StringToInteger(tk_part);
      if(tk == 0 || FindManagedIndex(tk) < 0)
         ObjectDelete(0, obj_n);
     }
  }

//+------------------------------------------------------------------+
//|  SaveStateForChartChange / RestoreStateFromChartChange           |
//|                                                                  |
//|  Persist the live panel state into terminal global variables so  |
//|  a timeframe switch (REASON_CHARTCHANGE) reloads the same setup  |
//|  instead of falling back to input defaults.                      |
//|                                                                  |
//|  The snapshot is consumed on restore and deleted, so it never    |
//|  survives a true EA restart or re-attach.                        |
//+------------------------------------------------------------------+

void SaveStateForChartChange()
  {
   GlobalVariableSet(GV_PFX + "valid",  1.0);
   GlobalVariableSet(GV_PFX + "action", (double)g_state.action);
   GlobalVariableSet(GV_PFX + "lots",   g_state.lots);
   GlobalVariableSet(GV_PFX + "rmode",  (double)g_state.risk_mode);
   GlobalVariableSet(GV_PFX + "rpct",   g_state.risk_percent);
   GlobalVariableSet(GV_PFX + "entry",  g_state.entry_price);
   GlobalVariableSet(GV_PFX + "sl",     g_state.sl_points);
   GlobalVariableSet(GV_PFX + "tp",     g_state.tp_points);
   GlobalVariableSet(GV_PFX + "msl",    g_state.market_sl_price);
   GlobalVariableSet(GV_PFX + "mtp",    g_state.market_tp_price);
   GlobalVariableSet(GV_PFX + "px",     (double)g_state.panel_x);
   GlobalVariableSet(GV_PFX + "py",     (double)g_state.panel_y);
   GlobalVariableSet(GV_PFX + "mini",   g_state.minimized ? 1.0 : 0.0);
  }

bool RestoreStateFromChartChange()
  {
   if(!GlobalVariableCheck(GV_PFX + "valid")) return false;
   if(GlobalVariableGet(GV_PFX + "valid") != 1.0)  return false;

   g_state.action       = (TradePanelAction)(int)GlobalVariableGet(GV_PFX + "action");
   g_state.lots         = GlobalVariableGet(GV_PFX + "lots");
   g_state.risk_mode    = (RiskMode)(int)GlobalVariableGet(GV_PFX + "rmode");
   g_state.risk_percent = GlobalVariableGet(GV_PFX + "rpct");
   g_state.entry_price  = GlobalVariableGet(GV_PFX + "entry");
   g_state.sl_points    = GlobalVariableGet(GV_PFX + "sl");
   g_state.tp_points    = GlobalVariableGet(GV_PFX + "tp");
   g_state.market_sl_price = GlobalVariableCheck(GV_PFX + "msl") ? GlobalVariableGet(GV_PFX + "msl") : 0.0;
   g_state.market_tp_price = GlobalVariableCheck(GV_PFX + "mtp") ? GlobalVariableGet(GV_PFX + "mtp") : 0.0;
   g_state.panel_x      = (int)GlobalVariableGet(GV_PFX + "px");
   g_state.panel_y      = (int)GlobalVariableGet(GV_PFX + "py");
   g_state.minimized    = GlobalVariableGet(GV_PFX + "mini") > 0.5;

   // Consume snapshot — do not persist beyond this init cycle
   GlobalVariableDel(GV_PFX + "valid");
   return true;
  }

//+------------------------------------------------------------------+
//|  CalcSmartInitDistance — symbol-aware initial SL/TP in points    |
//|                                                                  |
//|  Priority: ATR(14) > broker stop level floor > input default.    |
//|  Gives enough room to drag on first use without being huge.      |
//+------------------------------------------------------------------+

double CalcSmartInitDistance()
  {
   // ── 1. ATR(14) on previous closed bar ────────────────────────────
   int atr_h = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atr_h != INVALID_HANDLE)
     {
      double buf[1];
      if(CopyBuffer(atr_h, 0, 1, 1, buf) == 1 && buf[0] > 0.0)
        {
         IndicatorRelease(atr_h);
         double pts = MathRound(buf[0] / _Point);
         return MathMax(50.0, MathMin(10000.0, pts));   // clamp [50, 10000]
        }
      IndicatorRelease(atr_h);
     }

   // ── 2. Broker stop-level floor  ──────────────────────────────────
   int stop_lvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stop_lvl > 0)
     {
      double floor_pts = (double)(stop_lvl * 3 + 10);
      return MathMax(floor_pts, InpDefaultSlPoints);
     }

   // ── 3. Input default (last resort) ───────────────────────────────
   return MathMax(50.0, InpDefaultSlPoints);
  }
