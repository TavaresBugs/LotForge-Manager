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
   tp1_price          = 0.0;
   tp2_price          = 0.0;
   tp1_line_tooltip   = "";
   tp2_line_tooltip   = "";
   tp1_label          = "";
   tp2_label          = "";
  }

void SymbolRuntimeMetadata::Clear()
  {
   valid           = false;
   symbol          = "";
   digits          = 5;
   volume_min      = 0.01;
   volume_max      = 100.0;
   volume_step     = 0.01;
   tick_size       = 0.0;
   stops_level     = 0;
   freeze_level    = 0;
   revision        = 0;
   last_refresh_ms = 0;
  }

void PreviewFinancialKey::Clear()
  {
   valid            = false;
   action           = ACTION_NONE;
   risk_mode        = RISK_MODE_LOTS;
   risk_percent     = 0.0;
   risk_money       = 0.0;
   lots             = 0.0;
   entry_price      = 0.0;
   sl_price         = 0.0;
   tp_price         = 0.0;
   sl_points        = 0.0;
   tp_points        = 0.0;
   account_balance  = 0.0;
   metadata_revision = 0;
   tp_btn_state     = 0;
   tp1_points       = 0.0;
   tp2_points       = 0.0;
   tp1_lot_pct      = 0.0;
  }

void PreviewFinancialState::Clear()
  {
   ready              = false;
   plan_built         = false;
   plan_valid         = false;
   plan.Clear();
   build_reason       = "";
   validation_message = "";
  }

void PanelState::Init()
  {
   panel_x     = 30;
   panel_y     = 40;
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
   tp_btn_state       = 0;
   tp1_points         = MathMax(0.0, MathRound(InpDefaultTpPoints));
   tp2_points         = MathMax(0.0, MathRound(InpDefaultTpPoints + InpTpSplitOffsetPoints));
   tp1_lot_pct        = MathMin(99.0, MathMax(1.0, InpDefaultTp1Pct));
   tp2_linked         = true;
   market_tp1_price   = 0.0;
   market_tp2_price   = 0.0;
   risk_mode          = InpRiskMode;
   risk_percent       = InpRiskPercent;
   risk_money         = InpRiskMoney;
   entry_line_visible = false;
   sl_line_visible    = false;
   tp_line_visible    = false;
   break_even_enabled    = false;
   break_even_points     = 0;
   trailing_stop_enabled = false;
   trailing_stop_points  = 0;
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

void RequestManagedTradeMarkerCleanup()
  {
   g_managed_marker_cleanup_pending = true;
  }

int FindManagedTradeMarkerObjects(const string obj_id,
                                  string      &bg_n,
                                  string      &txt_n)
  {
   bg_n = MNGD_PFX + obj_id + "_bg";
   txt_n = MNGD_PFX + obj_id + "_tx";

   int found_mask = 0;
   if(ObjectFind(0, bg_n) >= 0)  found_mask |= 1;
   if(ObjectFind(0, txt_n) >= 0) found_mask |= 2;
   return found_mask;
  }

int FindManagedTradeMarkerKindObjects(const string tk_str,
                                      const string kind,
                                      string      &bg_n,
                                      string      &txt_n)
  {
   return FindManagedTradeMarkerObjects(tk_str + "_" + kind, bg_n, txt_n);
  }

//+------------------------------------------------------------------+
//|  ParseTpExitTagFromComment — recupera preços TP1/TP2 do comment  |
//|  Formato: "... TP1=1.23456 TP2=1.24567"                          |
//+------------------------------------------------------------------+

bool ParseTpExitTagFromComment(const string comment, double &tp1_out, double &tp2_out)
  {
   tp1_out = 0.0;
   tp2_out = 0.0;
   int pos1 = StringFind(comment, "TP1=");
   if(pos1 < 0) return false;
   tp1_out = StringToDouble(StringSubstr(comment, pos1 + 4));
   int pos2 = StringFind(comment, "TP2=");
   if(pos2 >= 0)
      tp2_out = StringToDouble(StringSubstr(comment, pos2 + 4));
   return (tp1_out > 0.0);
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

   bool already_protected = IsPositionProtected(ticket);
   ms.be_applied          = already_protected;

   string gv_iv  = GV_PFX + "iv_"  + IntegerToString(ticket);
   string gv_isl = GV_PFX + "isl_" + IntegerToString(ticket);

   if(!already_protected)
     {
      // New or unprotected position: record original volume and SL for trailing distance
      ms.initial_risk_points = (ms.initial_sl > 0.0)
                               ? MathAbs(ms.initial_open_price - ms.initial_sl) / _Point
                               : 0.0;
      GlobalVariableSet(gv_iv,  PositionGetDouble(POSITION_VOLUME));
      if(ms.initial_sl > 0.0)
         GlobalVariableSet(gv_isl, ms.initial_sl);
     }
   else
     {
      // Position already protected on EA reload: try to recover original SL distance
      // from the per-ticket GlobalVar saved at trade open.
      if(GlobalVariableCheck(gv_isl))
        {
         double orig_sl = GlobalVariableGet(gv_isl);
         ms.initial_risk_points = MathAbs(ms.initial_open_price - orig_sl) / _Point;
        }
      else
         ms.initial_risk_points = 0.0;
     }

   ms.trailing_armed = false;

   // ── TP exit system arming ────────────────────────────────────────
   // Priority 1: pending prices set by ProcessUiSend for this exact send
   if(g_pending_tp1_price > 0.0)
     {
      ms.managed_tp1_price = g_pending_tp1_price;
      ms.managed_tp2_price = g_pending_tp2_price;
      ms.tp_exits_enabled  = true;
      ms.tp1_done          = false;
      ms.tp2_done          = false;
      GlobalVariableSet(gv_iv, PositionGetDouble(POSITION_VOLUME));
      g_pending_tp1_price  = 0.0;   // consume — applies to first new trade only
      g_pending_tp2_price  = 0.0;
     }
   else
     {
      // Priority 2: recover from position comment tag on EA reload
      double rec_tp1 = 0.0, rec_tp2 = 0.0;
      string cmt = PositionGetString(POSITION_COMMENT);
      if(ParseTpExitTagFromComment(cmt, rec_tp1, rec_tp2))
        {
         ms.managed_tp1_price = rec_tp1;
         ms.managed_tp2_price = rec_tp2;
         ms.tp_exits_enabled  = true;
         // Bug D fix: if stored initial volume > current volume, TP1 partial was already done
         double cur_vol  = PositionGetDouble(POSITION_VOLUME);
         double orig_vol = GlobalVariableCheck(gv_iv) ? GlobalVariableGet(gv_iv) : cur_vol;
         ms.initial_volume = orig_vol;
         ms.tp1_done = (cur_vol < orig_vol - 1e-9);
         ms.tp2_done = false;
        }
      else
        {
         ms.managed_tp1_price = 0.0;
         ms.managed_tp2_price = 0.0;
         ms.tp_exits_enabled  = false;
         ms.tp1_done          = false;
         ms.tp2_done          = false;
        }
     }

   if(ms.initial_volume <= 0.0)
      ms.initial_volume = PositionGetDouble(POSITION_VOLUME);

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
     }

   // ── 2. Limpar entradas de posições já encerradas ──────────────────
   int n = ArraySize(g_managed_trades);
   for(int i = n - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(g_managed_trades[i].ticket))
        {
         // Apagar markers visuais antes de remover entrada
         EraseManagedTradeMarkers(g_managed_trades[i].ticket);
         RequestManagedTradeMarkerCleanup();
         // Limpar GlobalVars por ticket — posição encerrada
         string tk = IntegerToString(g_managed_trades[i].ticket);
         GlobalVariableDel(GV_PFX + "iv_"  + tk);
         GlobalVariableDel(GV_PFX + "isl_" + tk);
         // Remover entrada: shift para baixo
         for(int j = i; j < n - 1; j++)
            g_managed_trades[j] = g_managed_trades[j + 1];
         n--;
         ArrayResize(g_managed_trades, n);
        }
     }

   // ── 3. Atualizar flag global de TP exits ──────────────────────────
   g_tp_exits_active = false;
   for(int i = 0; i < n; i++)
      if(g_managed_trades[i].tp_exits_enabled)
        { g_tp_exits_active = true; break; }
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
   int stop_lvl = SymbolStopsLevelCached();
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
//|  TryTpExitClose — fecha parcialmente em TP1 e totalmente em TP2  |
//|  Substituiu o algo-parcial para trades com tp_exits_enabled.     |
//+------------------------------------------------------------------+

bool TryTpExitClose(const ulong ticket)
  {
   int idx = FindManagedIndex(ticket);
   if(idx < 0) return false;
   if(!g_managed_trades[idx].tp_exits_enabled) return false;
   if(g_managed_trades[idx].tp1_done && g_managed_trades[idx].tp2_done) return false;
   if(!PositionSelectByTicket(ticket)) return false;

   long   pos_type  = PositionGetInteger(POSITION_TYPE);
   bool   is_buy    = (pos_type == POSITION_TYPE_BUY);
   double price     = PositionGetDouble(POSITION_PRICE_CURRENT);
   double sl        = PositionGetDouble(POSITION_SL);
   double tp_broker = PositionGetDouble(POSITION_TP);
   double volume    = PositionGetDouble(POSITION_VOLUME);
   double vol_step  = EffectiveVolumeStep();
   double vol_min   = SymbolVolumeMinCached();

   // ── TP1 ───────────────────────────────────────────────────────────
   if(!g_managed_trades[idx].tp1_done)
     {
      double tp1 = g_managed_trades[idx].managed_tp1_price;
      if(tp1 <= 0.0)
        { g_managed_trades[idx].tp1_done = true; }   // não configurado — pular
      else
        {
         bool tp1_hit = is_buy ? (price >= tp1) : (price <= tp1);
         if(tp1_hit)
           {
            double close_pct   = MathMax(1.0, MathMin(100.0, InpDefaultTp1Pct));
            double init_vol    = g_managed_trades[idx].initial_volume;
            double tp1_vol_raw = MathFloor((init_vol * close_pct / 100.0) / vol_step) * vol_step;
            double tp1_vol     = MathMax(vol_min, tp1_vol_raw);
            // Nunca fechar mais do que o disponível menos o mínimo (manter posição viva para TP2)
            double max_vol = MathFloor((volume - vol_min) / vol_step) * vol_step;
            if(tp1_vol > max_vol) tp1_vol = max_vol;

            if(tp1_vol < vol_min)
              {
               g_managed_trades[idx].tp1_done = true;
               Print("[TP1 Exit] #", ticket, " volume insuficiente para parcial. Marcado como feito.");
              }
            else if(g_trade.PositionClosePartial(ticket, tp1_vol))
              {
               g_managed_trades[idx].tp1_done = true;
               string msg = StringFormat("TP1 Exit #%d: %.2f lots @ %s", ticket, tp1_vol, FormatPrice(price));
               SetStatus(msg, true);
               Print("[TP1 Exit] ", msg);
               return true;
              }
            else
              {
               int err = GetLastError();
               Print("[TP1 Exit] ERRO #", ticket, " err=", err);
               g_managed_trades[idx].tp1_done = true;   // evitar retry loop
               return false;
              }
           }
        }
     }

   // ── TP2 — só após TP1 concluído ───────────────────────────────────
   if(g_managed_trades[idx].tp1_done && !g_managed_trades[idx].tp2_done)
     {
      double tp2 = g_managed_trades[idx].managed_tp2_price;
      if(tp2 <= 0.0)
        { g_managed_trades[idx].tp2_done = true; }   // não configurado — broker TP cuida
      else
        {
         bool tp2_hit = is_buy ? (price >= tp2) : (price <= tp2);
         if(tp2_hit)
           {
            double close_pct   = MathMax(1.0, MathMin(100.0, 100.0));
            double tp2_vol_raw = MathFloor((volume * close_pct / 100.0) / vol_step) * vol_step;
            double tp2_vol     = MathMax(vol_min, tp2_vol_raw);
            bool   close_all   = (close_pct >= 100.0 || tp2_vol >= volume - vol_min * 0.5);
            bool   ok          = close_all ? g_trade.PositionClose(ticket)
                                           : g_trade.PositionClosePartial(ticket, tp2_vol);
            if(ok)
              {
               g_managed_trades[idx].tp2_done = true;
               string msg = close_all
                            ? StringFormat("TP2 Exit #%d: posição fechada @ %s", ticket, FormatPrice(price))
                            : StringFormat("TP2 Exit #%d: %.2f lots @ %s", ticket, tp2_vol, FormatPrice(price));
               SetStatus(msg, true);
               Print("[TP2 Exit] ", msg);
               return true;
              }
            else
              {
               Print("[TP2 Exit] ERRO #", ticket, " err=", GetLastError());
               g_managed_trades[idx].tp2_done = true;
               return false;
              }
           }
        }
     }

   return false;
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
   int stop_lvl = SymbolStopsLevelCached();
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

      // ── 1. Sincronizar proteção real — base para todas as decisões ─
      SyncProtectionState(i);

      // ── 2. Auto BE ────────────────────────────────────────────────
      if(auto_be_on)
         TryAutoBreakEven(t);

      // ── 3. Trailing (aproveita be_applied já sincronizado) ────────
      if(auto_trail_on)
         TryTrailingStop(t);

      // ── 4. TP Exit System (TP1/TP2 managed partial closes) ──────────
      bool tp_exits = g_managed_trades[i].tp_exits_enabled;
      if(tp_exits)
         TryTpExitClose(t);
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
//|  UpdateOpenTradeMarker — right-edge text label at price level     |
//|                                                                   |
//|  · OBJ_LABEL with CORNER_RIGHT_UPPER + ANCHOR_RIGHT              |
//|  · Pinned 5 px from chart right border, Y from price             |
//|  · No background bar — plain text only                           |
//+------------------------------------------------------------------+

bool GetPriceScreenY(const double price, int &out_y)
  {
   datetime t_bar0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t_bar0 == 0) return false;
   int px;
   if(!ChartTimePriceToXY(0, 0, t_bar0, price, px, out_y)) return false;
   int chart_h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(out_y < -OVL_BAR_H || out_y > chart_h + OVL_BAR_H) return false;
   return true;
  }

void EraseManagedTradeMarkerKind(const string tk_str, const string kind)
  {
   string bg_n, txt_n;
   int found_mask = FindManagedTradeMarkerKindObjects(tk_str, kind, bg_n, txt_n);
   if((found_mask & 1) != 0) ObjectDelete(0, bg_n);
   if((found_mask & 2) != 0) ObjectDelete(0, txt_n);
  }

bool ManagedTradeMarkerKindExists(const string tk_str, const string kind)
  {
   string bg_n, txt_n;
   return (FindManagedTradeMarkerKindObjects(tk_str, kind, bg_n, txt_n) != 0);
  }

bool UpdateOpenTradeMarkerGeometryOnly(const string obj_id,
                                       const double price,
                                       const bool   above_line)
  {
   string bg_n, txt_n;
   int found_mask = FindManagedTradeMarkerObjects(obj_id, bg_n, txt_n);

   // Clean up any legacy background bar
   if((found_mask & 1) != 0) ObjectDelete(0, bg_n);
   if((found_mask & 2) == 0) return false;

   string full_text = ObjectGetString(0, txt_n, OBJPROP_TOOLTIP);
   if(full_text == "")
      full_text = ObjectGetString(0, txt_n, OBJPROP_TEXT);
   if(full_text == "") return false;

   int py;
   if(!GetPriceScreenY(price, py))
     {
      ObjectDelete(0, txt_n);
      return true;
     }

   ObjectSetInteger(0, txt_n, OBJPROP_ANCHOR,
                    above_line ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, txt_n, OBJPROP_YDISTANCE, py + (above_line ? -4 : 4));
   return true;
  }

void UpdateOpenTradeMarker(const string obj_id,
                           const string text,
                           const double price,
                           const bool   above_line,
                           const color  bg_clr,
                           const color  border_clr,
                           const color  txt_clr)
  {
   string bg_n, txt_n;
   int found_mask = FindManagedTradeMarkerObjects(obj_id, bg_n, txt_n);

   // Clean up any legacy background bar
   if((found_mask & 1) != 0) ObjectDelete(0, bg_n);

   int py;
   if(!GetPriceScreenY(price, py))
     {
      if((found_mask & 2) != 0) ObjectDelete(0, txt_n);
      return;
     }

   // ── OBJ_LABEL right-edge text ─────────────────────────────────────
   if((found_mask & 2) == 0)
     {
      if(!ObjectCreate(0, txt_n, OBJ_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, txt_n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, txt_n, OBJPROP_HIDDEN,     false);
      ObjectSetInteger(0, txt_n, OBJPROP_BACK,       false);
      ObjectSetInteger(0, txt_n, OBJPROP_CORNER,     CORNER_RIGHT_UPPER);
      ApplyHandleLabelFont(txt_n);
     }
   ObjectSetInteger(0, txt_n, OBJPROP_XDISTANCE, 5);
   ObjectSetInteger(0, txt_n, OBJPROP_ANCHOR,
                    above_line ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, txt_n, OBJPROP_YDISTANCE, py + (above_line ? -4 : 4));
   ObjectSetString(0,  txt_n, OBJPROP_TEXT,      text);
   ObjectSetString(0,  txt_n, OBJPROP_TOOLTIP,   text);
   ObjectSetInteger(0, txt_n, OBJPROP_COLOR,     txt_clr);
  }

//+------------------------------------------------------------------+
//|  EraseManagedTradeMarkers — remove all marker objects for ticket  |
//+------------------------------------------------------------------+

void EraseManagedTradeMarkers(const ulong ticket)
  {
   string pfx = MNGD_PFX + IntegerToString(ticket) + "_";
   string tk_str = IntegerToString(ticket);
   string kinds[] = {"tp", "sl", "be", "tp1exit", "tp2exit"};
   int cnt = ArraySize(kinds);
   for(int i = 0; i < cnt; i++)
      EraseManagedTradeMarkerKind(tk_str, kinds[i]);
   // Release any adopted user line (clear tooltip tag, don't delete)
   string erase_marker = "#" + tk_str + " SL";
   int tot_h = ObjectsTotal(0, 0, OBJ_HLINE);
   for(int ai = 0; ai < tot_h; ai++)
     {
      string n = ObjectName(0, ai, 0, OBJ_HLINE);
      if(StringFind(n, PANEL_PREFIX) == 0) continue;
      if(StringFind(ObjectGetString(0, n, OBJPROP_TOOLTIP, 0), erase_marker) == 0)
        {
         ObjectSetString(0, n, OBJPROP_TOOLTIP, "");
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
         break;
        }
     }
   // SL / TP1 drag lines
   ObjectDelete(0, SLDR_PFX  + tk_str);
   ObjectDelete(0, TP1DR_PFX + tk_str);
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
      if(StringFind(n, MNGD_PFX) == 0 || StringFind(n, SLDR_PFX) == 0)
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

   int  mgd_idx      = FindManagedIndex(ticket);

   double vol_step_s = EffectiveVolumeStep();

   // ── TP markers ────────────────────────────────────────────────────
   bool tp_exits = (mgd_idx >= 0 && g_managed_trades[mgd_idx].tp_exits_enabled);

   if(tp_exits)
     {
      // TP exit mode: show TP1/TP2 exit markers; suppress generic tp
      EraseManagedTradeMarkerKind(tk_str, "tp");

      double init_vol  = g_managed_trades[mgd_idx].initial_volume;
      bool   tp1_done  = g_managed_trades[mgd_idx].tp1_done;
      bool   tp2_done  = g_managed_trades[mgd_idx].tp2_done;

      // ── TP1 exit marker ─────────────────────────────────────────
      double tp1_price = g_managed_trades[mgd_idx].managed_tp1_price;
      if(tp1_price > 0.0 && !tp1_done)
        {
         double close_pct_tp1 = MathMax(1.0, MathMin(100.0, InpDefaultTp1Pct));
         double tp1_close_vol = MathFloor((init_vol * close_pct_tp1 / 100.0) / vol_step_s) * vol_step_s;
         if(tp1_close_vol < vol_step_s) tp1_close_vol = vol_step_s;
         double tp1_money = 0.0; string tp1_r;
         CalcNetRewardMoneyForMove(open_price, tp1_price, tp1_close_vol, is_buy, tp1_money, tp1_r);
         tp1_money = NormalizeDouble(tp1_money, 2);
         string tp1_text = StringFormat("TP1 - %.0f%% l %.2f l +$%.2f",
                                        close_pct_tp1, tp1_close_vol, tp1_money);
         UpdateOpenTradeMarker(tk_str + "_tp1exit", tp1_text, tp1_price, is_buy,
                               CLR_OVL_HANDLE_BG, CLR_PREV_TP_BORDER, CLR_PREV_TP_TEXT);
        }
      else
         EraseManagedTradeMarkerKind(tk_str, "tp1exit");

      // ── TP2 exit marker ─────────────────────────────────────────
      double tp2_price = g_managed_trades[mgd_idx].managed_tp2_price;
      if(tp2_price > 0.0 && !tp2_done)
        {
         double close_pct_tp1 = MathMax(1.0, MathMin(100.0, InpDefaultTp1Pct));
         double close_pct_tp2 = MathMax(1.0, MathMin(100.0, 100.0));
         // Estimate remaining volume after TP1
         double tp1_vol_est   = MathFloor((init_vol * close_pct_tp1 / 100.0) / vol_step_s) * vol_step_s;
         double est_remaining = tp1_done ? volume
                                         : MathMax(vol_step_s, init_vol - tp1_vol_est);
         double tp2_close_vol = MathFloor((est_remaining * close_pct_tp2 / 100.0) / vol_step_s) * vol_step_s;
         if(tp2_close_vol < vol_step_s) tp2_close_vol = vol_step_s;
         double tp2_money = 0.0; string tp2_r;
         CalcNetRewardMoneyForMove(open_price, tp2_price, tp2_close_vol, is_buy, tp2_money, tp2_r);
         tp2_money = NormalizeDouble(tp2_money, 2);
         double tp2_pct_of_total = (init_vol > 0.0) ? tp2_close_vol / init_vol * 100.0 : close_pct_tp2;
         string tp2_text = StringFormat("TP2 - %.0f%% l %.2f l +$%.2f",
                                        tp2_pct_of_total, tp2_close_vol, tp2_money);
         UpdateOpenTradeMarker(tk_str + "_tp2exit", tp2_text, tp2_price, is_buy,
                               CLR_OVL_HANDLE_BG, C'100,180,120', C'20,120,50');
        }
      else
         EraseManagedTradeMarkerKind(tk_str, "tp2exit");
     }
   else
     {
      // Standard TP marker
      EraseManagedTradeMarkerKind(tk_str, "tp1exit");
      EraseManagedTradeMarkerKind(tk_str, "tp2exit");

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
         string tp_text = StringFormat("TP l %.2f l +$%.2f", volume, tp_money);
         UpdateOpenTradeMarker(tk_str + "_tp", tp_text, tp, is_buy,
                               CLR_OVL_HANDLE_BG, CLR_PREV_TP_BORDER, CLR_PREV_TP_TEXT);
        }
      else
         EraseManagedTradeMarkerKind(tk_str, "tp");
     }

   // ── Pre-compute BE state so SL marker is skipped when BE is active ──
   bool show_be_early = false;
   if(mgd_idx >= 0 && g_managed_trades[mgd_idx].be_applied && sl > 0.0)
     {
      if(is_buy && sl >= open_price)   show_be_early = true;
      else if(!is_buy && sl <= open_price) show_be_early = true;
     }

   // ── SL marker ─────────────────────────────────────────────────────
   if(sl > 0.0 && !show_be_early)
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

      bool sl_above = !is_buy;

      // ── Check if another managed position shares this SL price ────
      bool already_handled = false;
      int  handled_n = ArraySize(g_combined_sl_handled);
      for(int hi = 0; hi < handled_n; hi++)
         if(MathAbs(g_combined_sl_handled[hi] - sl) < _Point * 0.5)
           { already_handled = true; break; }

      if(already_handled)
        {
         // Primary ticket already drew the combined marker — erase individual
         EraseManagedTradeMarkerKind(tk_str, "sl");
        }
      else
        {
         // Scan for partners with same SL on this symbol
         double total_sl_money = sl_money;
         bool   has_partner    = false;
         int    mgd_n          = ArraySize(g_managed_trades);
         for(int pi = 0; pi < mgd_n; pi++)
           {
            ulong pt = g_managed_trades[pi].ticket;
            if(pt == ticket) continue;
            if(!PositionSelectByTicket(pt)) continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            double p_sl = PositionGetDouble(POSITION_SL);
            if(MathAbs(p_sl - sl) >= _Point * 0.5) continue;
            // Partner found
            has_partner = true;
            double p_open = PositionGetDouble(POSITION_PRICE_OPEN);
            double p_vol  = PositionGetDouble(POSITION_VOLUME);
            bool   p_buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            double p_risk = 0.0; string p_r;
            if(CalcNetRiskMoneyForMove(p_open, p_sl, p_vol, p_buy, p_risk, p_r))
               total_sl_money = NormalizeDouble(total_sl_money + p_risk, 2);
           }
         // Restore current position selection
         PositionSelectByTicket(ticket);

         if(has_partner)
           {
            // Register SL as handled so partners skip their individual markers
            ArrayResize(g_combined_sl_handled, handled_n + 1);
            g_combined_sl_handled[handled_n] = sl;

            double total_pct = 0.0;
            if(balance > 0.0)
               total_pct = NormalizeDouble(total_sl_money / balance * 100.0, 2);
            string sl_text = StringFormat("SL l -$%.2f combinado", total_sl_money);
            UpdateOpenTradeMarker(tk_str + "_sl", sl_text, sl, sl_above,
                                  CLR_OVL_HANDLE_BG, CLR_PREV_SL_BORDER, CLR_PREV_SL_TEXT);
           }
         else
           {
            string sl_text = StringFormat("SL l %.2f l -$%.2f", volume, sl_money);
            UpdateOpenTradeMarker(tk_str + "_sl", sl_text, sl, sl_above,
                                  CLR_OVL_HANDLE_BG, CLR_PREV_SL_BORDER, CLR_PREV_SL_TEXT);
           }
        }
     }
   else
      EraseManagedTradeMarkerKind(tk_str, "sl");

   // ── BE marker ─────────────────────────────────────────────────────
   //  Shows only when position is truly protected (SL on profitable side).
   //  Reflects actual SL level — not necessarily open_price.
   //  show_be_early already computed above — reuse to avoid duplicate logic.
   bool show_be = show_be_early;
   double be_price = show_be ? sl : 0.0;

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
         be_text = StringFormat("BE l %.2f l +$%.2f", volume, be_money);
      else
         be_text = "BE";

      // BE sits on the entry side: BUY → above_line=false (below entry), SELL → above_line=true
      bool be_above = !is_buy;
      UpdateOpenTradeMarker(tk_str + "_be", be_text, be_price, be_above,
                            CLR_OVL_HANDLE_BG, CLR_BE_BORDER, C'140,90,0');
     }
   else
      EraseManagedTradeMarkerKind(tk_str, "be");

   // ── TP1 exit drag line ────────────────────────────────────────────
   if(tp_exits && !g_managed_trades[mgd_idx].tp1_done)
     {
      double tp1_drag_price = g_managed_trades[mgd_idx].managed_tp1_price;
      string tp1dr_name     = TP1DR_PFX + tk_str;
      string tp1dr_tip      = StringFormat("#%s TP1 Exit — arraste para mover", tk_str);

      if(tp1_drag_price > 0.0)
        {
         if(ObjectFind(0, tp1dr_name) < 0)
           {
            ObjectCreate(0, tp1dr_name, OBJ_HLINE, 0, 0, tp1_drag_price);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_COLOR,      CLR_PREV_SL_BORDER);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_STYLE,      STYLE_DASHDOT);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_WIDTH,      1);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_BACK,       false);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_SELECTED,   false);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_HIDDEN,     false);
            ObjectSetString(0,  tp1dr_name, OBJPROP_TOOLTIP,    tp1dr_tip);
           }
         else
           {
            if(!g_tp1_drag_active || g_tp1_drag_ticket != g_managed_trades[mgd_idx].ticket)
               ObjectSetDouble(0, tp1dr_name, OBJPROP_PRICE, tp1_drag_price);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_COLOR,      CLR_PREV_SL_BORDER);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_STYLE,      STYLE_DASHDOT);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_WIDTH,      1);
            ObjectSetInteger(0, tp1dr_name, OBJPROP_SELECTABLE, false);
            ObjectSetString(0,  tp1dr_name, OBJPROP_TOOLTIP,    tp1dr_tip);
           }
        }
      else
         ObjectDelete(0, tp1dr_name);
     }
   else
      ObjectDelete(0, TP1DR_PFX + tk_str);

   // ── SL drag handle — adopt user OBJ_HLINE at SL price, else own SLDR ──
   // Tag mechanism: adopted line gets our tooltip "#{ticket} SL — ..."
   // OBJPROP_TOOLTIP is non-visual (hover only) — no visible change to user line.
   string sldr_name    = SLDR_PFX + tk_str;
   string adopt_tip    = StringFormat("#%s SL — arraste para modificar | snap %d pts",
                                      tk_str, InpSlSnapPoints);
   string adopt_marker = "#" + tk_str + " SL";   // prefix to detect our tag
   double adopt_tol    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(adopt_tol <= 0.0) adopt_tol = _Point;

   if(sl > 0.0)
     {
      // ── 1. Find already-adopted user line (our tooltip prefix, not SLDR) ─
      string adopted_name = "";
      int total_h = ObjectsTotal(0, 0, OBJ_HLINE);
      for(int ai = 0; ai < total_h; ai++)
        {
         string n = ObjectName(0, ai, 0, OBJ_HLINE);
         if(StringFind(n, PANEL_PREFIX) == 0) continue;
         if(StringFind(ObjectGetString(0, n, OBJPROP_TOOLTIP, 0), adopt_marker) == 0)
           { adopted_name = n; break; }
        }

      // ── 2. Validate existing adoption (price must still match SL) ─────
      if(adopted_name != "")
        {
         bool dragging = (bool)ObjectGetInteger(0, adopted_name, OBJPROP_SELECTED);
         if(!dragging)
           {
            double ln_price = ObjectGetDouble(0, adopted_name, OBJPROP_PRICE);
            if(MathAbs(ln_price - sl) > adopt_tol)
              {
               // SL moved externally — release adoption, keep user line intact
               ObjectSetString(0, adopted_name, OBJPROP_TOOLTIP, "");
               ObjectSetInteger(0, adopted_name, OBJPROP_SELECTABLE, false);
               adopted_name = "";
              }
           }
        }

      // ── 3. Refresh adopted line ────────────────────────────────────────
      if(adopted_name != "")
        {
         ObjectSetInteger(0, adopted_name, OBJPROP_SELECTABLE, true);
         ObjectSetString(0, adopted_name, OBJPROP_TOOLTIP, adopt_tip);
         ObjectDelete(0, sldr_name);   // remove our duplicate if any
        }

      // ── 4. Try to adopt a nearby user line ────────────────────────────
      if(adopted_name == "")
        {
         total_h = ObjectsTotal(0, 0, OBJ_HLINE);
         for(int ai = 0; ai < total_h; ai++)
           {
            string n = ObjectName(0, ai, 0, OBJ_HLINE);
            if(StringFind(n, PANEL_PREFIX) == 0) continue;   // skip our objects
            // Skip if already adopted by another position (tooltip contains " SL — ")
            if(StringFind(ObjectGetString(0, n, OBJPROP_TOOLTIP, 0), " SL — ") >= 0) continue;
            double lp = ObjectGetDouble(0, n, OBJPROP_PRICE);
            if(MathAbs(lp - sl) <= adopt_tol)
              {
               ObjectSetInteger(0, n, OBJPROP_SELECTABLE, true);
               ObjectSetString(0, n, OBJPROP_TOOLTIP, adopt_tip);
               ObjectDelete(0, sldr_name);
               adopted_name = n;
               break;
              }
           }
        }

      // ── 5. No user line to adopt — no drag handle created (stealth) ────
      // Delete any stale SLDR from previous sessions
      if(adopted_name == "")
         ObjectDelete(0, sldr_name);
     }
   else
     {
      // SL = 0 — release any adoption, delete our SLDR
      int total_h = ObjectsTotal(0, 0, OBJ_HLINE);
      for(int ai = 0; ai < total_h; ai++)
        {
         string n = ObjectName(0, ai, 0, OBJ_HLINE);
         if(StringFind(n, PANEL_PREFIX) == 0) continue;
         if(StringFind(ObjectGetString(0, n, OBJPROP_TOOLTIP, 0), adopt_marker) == 0)
           {
            ObjectSetString(0, n, OBJPROP_TOOLTIP, "");
            ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
            break;
           }
        }
      ObjectDelete(0, sldr_name);
     }
  }

bool UpdateManagedTradeMarkersGeometryOnly(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;

   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl         = PositionGetDouble(POSITION_SL);
   double tp         = PositionGetDouble(POSITION_TP);
   long   pos_type   = PositionGetInteger(POSITION_TYPE);
   bool   is_buy     = (pos_type == POSITION_TYPE_BUY);

   string tk_str  = IntegerToString(ticket);
   int    mgd_idx = FindManagedIndex(ticket);
   bool   tp_exits = (mgd_idx >= 0 && g_managed_trades[mgd_idx].tp_exits_enabled);

   // ── TP markers ────────────────────────────────────────────────────
   if(tp_exits)
     {
      // TP1 exit
      double tp1_price = g_managed_trades[mgd_idx].managed_tp1_price;
      bool   tp1_done  = g_managed_trades[mgd_idx].tp1_done;
      if(tp1_price > 0.0 && !tp1_done)
        {
         if(!UpdateOpenTradeMarkerGeometryOnly(tk_str + "_tp1exit", tp1_price, is_buy))
            return false;
        }
      else if(ManagedTradeMarkerKindExists(tk_str, "tp1exit"))
         return false;

      // TP2 exit
      double tp2_price = g_managed_trades[mgd_idx].managed_tp2_price;
      bool   tp2_done  = g_managed_trades[mgd_idx].tp2_done;
      if(tp2_price > 0.0 && !tp2_done)
        {
         if(!UpdateOpenTradeMarkerGeometryOnly(tk_str + "_tp2exit", tp2_price, is_buy))
            return false;
        }
      else if(ManagedTradeMarkerKindExists(tk_str, "tp2exit"))
         return false;
     }
   else
     {
      if(tp > 0.0)
        {
         if(!UpdateOpenTradeMarkerGeometryOnly(tk_str + "_tp", tp, is_buy))
            return false;
        }
      else if(ManagedTradeMarkerKindExists(tk_str, "tp"))
         return false;
     }

   // ── BE state (suppresses SL marker) ──────────────────────────────
   bool   show_be  = false;
   double be_price = 0.0;
   if(mgd_idx >= 0 && g_managed_trades[mgd_idx].be_applied && sl > 0.0)
     {
      if(is_buy && sl >= open_price)
        { show_be = true; be_price = sl; }
      else if(!is_buy && sl <= open_price)
        { show_be = true; be_price = sl; }
     }

   // ── SL marker ─────────────────────────────────────────────────────
   if(!show_be)
     {
      if(sl > 0.0)
        {
         if(!UpdateOpenTradeMarkerGeometryOnly(tk_str + "_sl", sl, !is_buy))
            return false;
        }
      else if(ManagedTradeMarkerKindExists(tk_str, "sl"))
         return false;
     }

   // ── BE marker ─────────────────────────────────────────────────────
   if(show_be)
     {
      if(!UpdateOpenTradeMarkerGeometryOnly(tk_str + "_be", be_price, !is_buy))
         return false;
     }
   else if(ManagedTradeMarkerKindExists(tk_str, "be"))
      return false;

   return true;
  }

void CleanOrphanManagedTradeMarkers()
  {
   // ── Clean orphan marker objects (tickets no longer in array) ──────
   //  This is intentionally invalidation-driven; do not scan all chart
   //  objects on every tick when the tracked ticket set has not changed.
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string obj_n = ObjectName(0, i, 0, -1);
      if(StringFind(obj_n, MNGD_PFX) != 0) continue;
      string remainder = StringSubstr(obj_n, StringLen(MNGD_PFX));
      int sep = StringFind(remainder, "_");
      if(sep <= 0) { ObjectDelete(0, obj_n); continue; }
      string tk_part = StringSubstr(remainder, 0, sep);
      ulong tk = (ulong)StringToInteger(tk_part);
      if(tk == 0 || FindManagedIndex(tk) < 0)
         ObjectDelete(0, obj_n);
     }
  }

bool RefreshManagedTradeMarkersGeometryOnly()
  {
   int n = ArraySize(g_managed_trades);
   for(int i = 0; i < n; i++)
     {
      ulong t = g_managed_trades[i].ticket;
      if(!UpdateManagedTradeMarkersGeometryOnly(t))
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//|  RefreshAllManagedTradeMarkers — called from OnTick after sync   |
//+------------------------------------------------------------------+

void RefreshAllManagedTradeMarkers()
  {
   // ── Reset combined-SL tracking for this cycle ─────────────────────
   ArrayResize(g_combined_sl_handled, 0);

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

   if(g_managed_marker_cleanup_pending)
     {
      g_managed_marker_cleanup_pending = false;
      CleanOrphanManagedTradeMarkers();
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
   GlobalVariableSet(GV_PFX + "valid",      1.0);
   GlobalVariableSet(GV_PFX + "action",     (double)g_state.action);
   GlobalVariableSet(GV_PFX + "lots",       g_state.lots);
   GlobalVariableSet(GV_PFX + "rmode",      (double)g_state.risk_mode);
   GlobalVariableSet(GV_PFX + "rpct",       g_state.risk_percent);
   GlobalVariableSet(GV_PFX + "rmoney",     g_state.risk_money);
   GlobalVariableSet(GV_PFX + "entry",      g_state.entry_price);
   GlobalVariableSet(GV_PFX + "sl",         g_state.sl_points);
   GlobalVariableSet(GV_PFX + "tp",         g_state.tp_points);
   GlobalVariableSet(GV_PFX + "msl",        g_state.market_sl_price);
   GlobalVariableSet(GV_PFX + "mtp",        g_state.market_tp_price);
   GlobalVariableSet(GV_PFX + "px",         (double)g_state.panel_x);
   GlobalVariableSet(GV_PFX + "py",         (double)g_state.panel_y);
   GlobalVariableSet(GV_PFX + "mini",       g_state.minimized ? 1.0 : 0.0);
   GlobalVariableSet(GV_PFX + "tpbtnstate", (double)g_state.tp_btn_state);
   GlobalVariableSet(GV_PFX + "tp1",        g_state.tp1_points);
   GlobalVariableSet(GV_PFX + "tp2",        g_state.tp2_points);
   GlobalVariableSet(GV_PFX + "tp1pct",     g_state.tp1_lot_pct);
   GlobalVariableSet(GV_PFX + "tp2lnk",     g_state.tp2_linked ? 1.0 : 0.0);
  }

bool RestoreStateFromChartChange()
  {
   if(!GlobalVariableCheck(GV_PFX + "valid")) return false;
   if(GlobalVariableGet(GV_PFX + "valid") != 1.0)  return false;

   g_state.action       = (TradePanelAction)(int)GlobalVariableGet(GV_PFX + "action");
   g_state.lots         = GlobalVariableCheck(GV_PFX + "lots")  ? GlobalVariableGet(GV_PFX + "lots")  : InpDefaultLots;
   if(g_state.lots <= 0.0) g_state.lots = NormalizeVolumeValue(InpDefaultLots);
   g_state.risk_mode    = (RiskMode)(int)GlobalVariableGet(GV_PFX + "rmode");
   g_state.risk_percent = GlobalVariableCheck(GV_PFX + "rpct")  ? GlobalVariableGet(GV_PFX + "rpct")  : InpRiskPercent;
   if(g_state.risk_percent <= 0.0) g_state.risk_percent = InpRiskPercent;
   g_state.risk_money   = GlobalVariableCheck(GV_PFX + "rmoney") ? GlobalVariableGet(GV_PFX + "rmoney") : InpRiskMoney;
   if(g_state.risk_money <= 0.0) g_state.risk_money = InpRiskMoney;
   g_state.entry_price  = GlobalVariableGet(GV_PFX + "entry");
   g_state.sl_points    = GlobalVariableGet(GV_PFX + "sl");
   g_state.tp_points    = GlobalVariableGet(GV_PFX + "tp");
   g_state.market_sl_price = GlobalVariableCheck(GV_PFX + "msl") ? GlobalVariableGet(GV_PFX + "msl") : 0.0;
   g_state.market_tp_price = GlobalVariableCheck(GV_PFX + "mtp") ? GlobalVariableGet(GV_PFX + "mtp") : 0.0;
   g_state.panel_x      = (int)GlobalVariableGet(GV_PFX + "px");
   g_state.panel_y      = (int)GlobalVariableGet(GV_PFX + "py");
   g_state.minimized    = GlobalVariableGet(GV_PFX + "mini") > 0.5;
   g_state.tp_btn_state = GlobalVariableCheck(GV_PFX + "tpbtnstate") ? (int)GlobalVariableGet(GV_PFX + "tpbtnstate") : 0;
   g_state.tp_btn_state = (g_state.tp_btn_state > 0) ? 1 : 0;
   g_state.tp1_points   = GlobalVariableCheck(GV_PFX + "tp1") ? GlobalVariableGet(GV_PFX + "tp1") : g_state.tp_points;
   g_state.tp2_points   = GlobalVariableCheck(GV_PFX + "tp2") ? GlobalVariableGet(GV_PFX + "tp2") : g_state.tp_points + InpTpSplitOffsetPoints;
   g_state.tp1_lot_pct  = GlobalVariableCheck(GV_PFX + "tp1pct") ? GlobalVariableGet(GV_PFX + "tp1pct") : InpDefaultTp1Pct;
   g_state.tp2_linked   = GlobalVariableCheck(GV_PFX + "tp2lnk") ? (GlobalVariableGet(GV_PFX + "tp2lnk") > 0.5) : true;
   g_state.market_tp1_price = 0.0;
   g_state.market_tp2_price = 0.0;
   if(IsDualTPMode())
      EnforceDualTpInvariant(false, false);

   // Consume snapshot — do not persist beyond this init cycle
   GlobalVariableDel(GV_PFX + "valid");
   return true;
  }

//+------------------------------------------------------------------+
//|  SaveSessionState / RestoreSessionState                          |
//|                                                                  |
//|  Persist panel UI state across full MT5 restarts (not just TF   |
//|  changes). Uses "ssn_" prefix so it never collides with the TF  |
//|  change "valid" key. Overwritten on every clean shutdown.        |
//+------------------------------------------------------------------+

void SaveSessionState()
  {
   GlobalVariableSet(GV_PFX + "ssn",        1.0);
   GlobalVariableSet(GV_PFX + "ssn_lots",   g_state.lots);
   GlobalVariableSet(GV_PFX + "ssn_rmode",  (double)g_state.risk_mode);
   GlobalVariableSet(GV_PFX + "ssn_rpct",   g_state.risk_percent);
   GlobalVariableSet(GV_PFX + "ssn_rmoney", g_state.risk_money);
   GlobalVariableSet(GV_PFX + "ssn_entry",  g_state.entry_price);
   GlobalVariableSet(GV_PFX + "ssn_sl",     g_state.sl_points);
   GlobalVariableSet(GV_PFX + "ssn_tp",     g_state.tp_points);
   GlobalVariableSet(GV_PFX + "ssn_msl",    g_state.market_sl_price);
   GlobalVariableSet(GV_PFX + "ssn_mtp",    g_state.market_tp_price);
   GlobalVariableSet(GV_PFX + "ssn_px",     (double)g_state.panel_x);
   GlobalVariableSet(GV_PFX + "ssn_py",     (double)g_state.panel_y);
   GlobalVariableSet(GV_PFX + "ssn_mini",   g_state.minimized ? 1.0 : 0.0);
   GlobalVariableSet(GV_PFX + "ssn_tpbtn",  (double)g_state.tp_btn_state);
   GlobalVariableSet(GV_PFX + "ssn_tp1",    g_state.tp1_points);
   GlobalVariableSet(GV_PFX + "ssn_tp2",    g_state.tp2_points);
   GlobalVariableSet(GV_PFX + "ssn_tp1pct", g_state.tp1_lot_pct);
   GlobalVariableSet(GV_PFX + "ssn_tp2lnk", g_state.tp2_linked ? 1.0 : 0.0);
  }

void RestoreSessionState()
  {
   if(!GlobalVariableCheck(GV_PFX + "ssn")) return;
   if(GlobalVariableGet(GV_PFX + "ssn") != 1.0) return;

   double v;
   if(GlobalVariableCheck(GV_PFX + "ssn_lots"))
     { v = GlobalVariableGet(GV_PFX + "ssn_lots"); if(v > 0.0) g_state.lots = v; }
   if(GlobalVariableCheck(GV_PFX + "ssn_rmode"))
      g_state.risk_mode = (RiskMode)(int)GlobalVariableGet(GV_PFX + "ssn_rmode");
   if(GlobalVariableCheck(GV_PFX + "ssn_rpct"))
     { v = GlobalVariableGet(GV_PFX + "ssn_rpct"); if(v > 0.0) g_state.risk_percent = v; }
   if(GlobalVariableCheck(GV_PFX + "ssn_rmoney"))
     { v = GlobalVariableGet(GV_PFX + "ssn_rmoney"); if(v > 0.0) g_state.risk_money = v; }
   if(GlobalVariableCheck(GV_PFX + "ssn_entry"))
      g_state.entry_price = GlobalVariableGet(GV_PFX + "ssn_entry");
   if(GlobalVariableCheck(GV_PFX + "ssn_sl"))
     { v = GlobalVariableGet(GV_PFX + "ssn_sl"); if(v > 0.0) g_state.sl_points = v; }
   if(GlobalVariableCheck(GV_PFX + "ssn_tp"))
     { v = GlobalVariableGet(GV_PFX + "ssn_tp"); if(v > 0.0) g_state.tp_points = v; }
   if(GlobalVariableCheck(GV_PFX + "ssn_msl"))
      g_state.market_sl_price = GlobalVariableGet(GV_PFX + "ssn_msl");
   if(GlobalVariableCheck(GV_PFX + "ssn_mtp"))
      g_state.market_tp_price = GlobalVariableGet(GV_PFX + "ssn_mtp");
   if(GlobalVariableCheck(GV_PFX + "ssn_px"))
     { int px = (int)GlobalVariableGet(GV_PFX + "ssn_px"); if(px > 0) g_state.panel_x = px; }
   if(GlobalVariableCheck(GV_PFX + "ssn_py"))
     { int py = (int)GlobalVariableGet(GV_PFX + "ssn_py"); if(py > 0) g_state.panel_y = py; }
   if(GlobalVariableCheck(GV_PFX + "ssn_mini"))
      g_state.minimized = GlobalVariableGet(GV_PFX + "ssn_mini") > 0.5;
   if(GlobalVariableCheck(GV_PFX + "ssn_tpbtn"))
      g_state.tp_btn_state = (int)GlobalVariableGet(GV_PFX + "ssn_tpbtn") > 0 ? 1 : 0;
   if(GlobalVariableCheck(GV_PFX + "ssn_tp1"))
     { v = GlobalVariableGet(GV_PFX + "ssn_tp1"); if(v > 0.0) g_state.tp1_points = v; }
   if(GlobalVariableCheck(GV_PFX + "ssn_tp2"))
     { v = GlobalVariableGet(GV_PFX + "ssn_tp2"); if(v > 0.0) g_state.tp2_points = v; }
   if(GlobalVariableCheck(GV_PFX + "ssn_tp1pct"))
     { v = GlobalVariableGet(GV_PFX + "ssn_tp1pct"); if(v > 0.0) g_state.tp1_lot_pct = v; }
   if(GlobalVariableCheck(GV_PFX + "ssn_tp2lnk"))
      g_state.tp2_linked = GlobalVariableGet(GV_PFX + "ssn_tp2lnk") > 0.5;

   if(IsDualTPMode())
      EnforceDualTpInvariant(false, false);
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
   int stop_lvl = SymbolStopsLevelCached();
   if(stop_lvl > 0)
     {
      double floor_pts = (double)(stop_lvl * 3 + 10);
      return MathMax(floor_pts, InpDefaultSlPoints);
     }

   // ── 3. Input default (last resort) ───────────────────────────────
   return MathMax(50.0, InpDefaultSlPoints);
  }
