//+------------------------------------------------------------------+
//|  ██  FASE 4A — Planning & Validation Layer                       |
//+------------------------------------------------------------------+

string g_conversion_symbols[];
bool   g_conversion_symbols_cached = false;

string NormalizeCurrencyCode(const string currency)
  {
   if(currency == "RUR") return "RUB";
   return currency;
  }

bool IsForexCalcMode(const ENUM_SYMBOL_CALC_MODE calc_mode)
  {
   return (calc_mode == SYMBOL_CALC_MODE_FOREX ||
           calc_mode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE);
  }

void EnsureConversionSymbolCache()
  {
   if(g_conversion_symbols_cached)
      return;

   ArrayResize(g_conversion_symbols, 0);

   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
     {
      string symbol = SymbolName(i, false);
      ENUM_SYMBOL_CALC_MODE mode =
         (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE);
      if(!IsForexCalcMode(mode))
         continue;

      int size = ArraySize(g_conversion_symbols);
      ArrayResize(g_conversion_symbols, size + 1, 128);
      g_conversion_symbols[size] = symbol;
     }

   g_conversion_symbols_cached = true;
  }

string FindConversionSymbolByCurrencies(const string base_currency,
                                        const string profit_currency)
  {
   if(base_currency == "" || profit_currency == "")
      return "";

   EnsureConversionSymbolCache();

   int total = ArraySize(g_conversion_symbols);
   for(int i = 0; i < total; i++)
     {
      string symbol = g_conversion_symbols[i];
      if(SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE) != base_currency)
         continue;
      if(SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT) != profit_currency)
         continue;

      if(!(bool)SymbolInfoInteger(symbol, SYMBOL_SELECT))
         SymbolSelect(symbol, true);

      return symbol;
     }

   return "";
  }

bool CalcCurrencyConversionRate(const string from_currency,
                                const string to_currency,
                                const bool   for_profit,
                                double      &out_rate,
                                string      &out_reason)
  {
   out_rate   = 1.0;
   out_reason = "";

   string from_ccy = NormalizeCurrencyCode(from_currency);
   string to_ccy   = NormalizeCurrencyCode(to_currency);
   if(from_ccy == to_ccy)
      return true;
   if(from_ccy == "" || to_ccy == "")
     {
      out_reason = "Erro: moeda inválida para conversão financeira.";
      return false;
     }

   MqlTick tick;
   string symbol = FindConversionSymbolByCurrencies(from_ccy, to_ccy);
   if(symbol != "")
     {
      if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
        {
         out_reason = "Erro: cotação indisponível para conversão financeira.";
         return false;
        }
      out_rate = for_profit ? tick.bid : tick.ask;
      return true;
     }

   symbol = FindConversionSymbolByCurrencies(to_ccy, from_ccy);
   if(symbol != "")
     {
      if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
        {
         out_reason = "Erro: cotação indisponível para conversão financeira.";
         return false;
        }
      out_rate = for_profit ? (1.0 / tick.ask) : (1.0 / tick.bid);
      return true;
     }

   if(from_ccy != "USD" && to_ccy != "USD")
     {
      double leg_1 = 0.0, leg_2 = 0.0;
      string leg_reason;
      if(CalcCurrencyConversionRate(from_ccy, "USD", for_profit, leg_1, leg_reason) &&
         CalcCurrencyConversionRate("USD", to_ccy, for_profit, leg_2, leg_reason))
        {
         out_rate = leg_1 * leg_2;
         return true;
        }
     }

   out_reason = StringFormat("Erro: não foi possível converter %s para %s.", from_ccy, to_ccy);
   return false;
  }

bool ConvertMoneyToAccountCurrency(const double money,
                                   const string from_currency,
                                   const bool   for_profit,
                                   double      &out_money,
                                   string      &out_reason)
  {
   out_money  = money;
   out_reason = "";

   string account_currency = NormalizeCurrencyCode(AccountInfoString(ACCOUNT_CURRENCY));
   string source_currency  = NormalizeCurrencyCode(from_currency);
   if(source_currency == account_currency || money == 0.0)
      return true;

   double rate = 1.0;
   if(!CalcCurrencyConversionRate(source_currency, account_currency, for_profit, rate, out_reason))
      return false;

   out_money = money * rate;
   return true;
  }

bool CalcSymbolPnLForMoveManual(const double open_price,
                                const double close_price,
                                const double volume,
                                const bool   is_buy,
                                double      &out_money,
                                string      &out_reason)
  {
   out_money  = 0.0;
   out_reason = "";

   double signed_price_move = is_buy ? (close_price - open_price)
                                     : (open_price - close_price);
   if(MathAbs(signed_price_move) < 1e-12)
      return true;

   ENUM_SYMBOL_CALC_MODE calc_mode =
      (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE);
   string account_currency = NormalizeCurrencyCode(AccountInfoString(ACCOUNT_CURRENCY));
   string profit_currency  = NormalizeCurrencyCode(SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT));
   string base_currency    = NormalizeCurrencyCode(SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE));
   bool   is_profit_move   = (signed_price_move > 0.0);
   double raw_money        = 0.0;

   switch(calc_mode)
     {
      case SYMBOL_CALC_MODE_FOREX:
      case SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE:
      case SYMBOL_CALC_MODE_CFD:
      case SYMBOL_CALC_MODE_CFDINDEX:
      case SYMBOL_CALC_MODE_CFDLEVERAGE:
      case SYMBOL_CALC_MODE_EXCH_STOCKS:
      case SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX:
        {
         double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         if(contract_size <= 0.0)
           {
            out_reason = "Erro: contract size indisponível para fallback financeiro.";
            return false;
           }
         raw_money = signed_price_move * contract_size * volume;
         break;
        }

      case SYMBOL_CALC_MODE_FUTURES:
      case SYMBOL_CALC_MODE_EXCH_FUTURES:
      case SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS:
        {
         double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tick_value = SymbolInfoDouble(
            _Symbol,
            is_profit_move ? SYMBOL_TRADE_TICK_VALUE_PROFIT
                           : SYMBOL_TRADE_TICK_VALUE_LOSS);
         if(tick_value <= 0.0)
            tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tick_size <= 0.0 || tick_value <= 0.0)
           {
            out_reason = "Erro: tick size/value indisponível para fallback financeiro.";
            return false;
           }
         raw_money = signed_price_move / tick_size * tick_value * volume;
         break;
        }

      default:
        {
         out_reason = StringFormat("Erro: fallback financeiro não suporta calc mode %d.", (int)calc_mode);
         return false;
        }
     }

   if(account_currency == profit_currency || profit_currency == "")
     {
      out_money = raw_money;
      return true;
     }

   if(IsForexCalcMode(calc_mode) && account_currency == base_currency && close_price > 0.0)
     {
      out_money = raw_money / close_price;
      return true;
     }

   double converted = 0.0;
   if(!ConvertMoneyToAccountCurrency(MathAbs(raw_money), profit_currency, is_profit_move, converted, out_reason))
      return false;

   out_money = (raw_money >= 0.0) ? converted : -converted;
   return true;
  }

double CalcRoundTripCommissionMoney(const double volume)
  {
   if(volume <= 0.0)
      return 0.0;

   double per_side = MathMax(0.0, InpCommissionPerLot);
   return per_side * volume * 2.0;
  }

bool CalcNetRiskMoneyForMove(const double open_price,
                             const double close_price,
                             const double volume,
                             const bool   is_buy,
                             double      &out_money,
                             string      &out_reason)
  {
   out_money  = 0.0;
   out_reason = "";

   double raw_money = 0.0;
   if(!CalcSymbolPnLForMove(open_price, close_price, volume, is_buy, raw_money, out_reason))
      return false;

   out_money = MathAbs(raw_money) + CalcRoundTripCommissionMoney(volume);
   return true;
  }

bool CalcNetRewardMoneyForMove(const double open_price,
                               const double close_price,
                               const double volume,
                               const bool   is_buy,
                               double      &out_money,
                               string      &out_reason)
  {
   out_money  = 0.0;
   out_reason = "";

   double raw_money = 0.0;
   if(!CalcSymbolPnLForMove(open_price, close_price, volume, is_buy, raw_money, out_reason))
      return false;

   out_money = MathMax(0.0, raw_money - CalcRoundTripCommissionMoney(volume));
   return true;
  }

bool CalcSymbolPnLForMove(const double open_price,
                          const double close_price,
                          const double volume,
                          const bool   is_buy,
                          double      &out_money,
                          string      &out_reason)
  {
   out_money  = 0.0;
   out_reason = "";

   if(open_price <= 0.0 || close_price <= 0.0)
     {
      out_reason = "Erro: preços inválidos para cálculo financeiro.";
      return false;
     }
   if(volume <= 0.0)
     {
      out_reason = "Erro: volume inválido para cálculo financeiro.";
      return false;
     }

   ENUM_ORDER_TYPE order_type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(order_type, _Symbol, volume, open_price, close_price, out_money))
      return true;

   return CalcSymbolPnLForMoveManual(open_price, close_price, volume, is_buy, out_money, out_reason);
  }

//+------------------------------------------------------------------+
//|  CalcLotsFromRiskPercent                                         |
//|                                                                  |
//|  Derives position size from account risk %.                      |
//|  Uses symbol-aware profit/loss for a 1-lot move from entry to SL |
//|  then scales lots conservatively to the broker step grid.        |
//|                                                                  |
//|  Returns false (with out_lots = 0) on any invalid input or       |
//|  data unavailability — no silent fallbacks.                      |
//+------------------------------------------------------------------+

bool CalcLotsFromRiskPercent(const double entry_price, const double sl_price,
                             const bool is_buy, double &out_lots, string &out_reason)
  {
   out_lots   = 0.0;
   out_reason = "";

   // ── Sanity: prices must be positive and distinct ─────────────────
   if(entry_price <= 0.0 || sl_price <= 0.0)
     { out_reason = "Erro: preço de entrada ou SL inválido para cálculo de lote."; return false; }

   double sl_dist = MathAbs(entry_price - sl_price);
   if(sl_dist < _Point * 0.5)
     { out_reason = "Erro: SL inválido para calcular lote por risco."; return false; }

   // ── Semantic sanity: SL must be on the correct side ──────────────
   if(is_buy  && sl_price >= entry_price)
     { out_reason = "Erro: SL de compra deve estar abaixo da entrada."; return false; }
   if(!is_buy && sl_price <= entry_price)
     { out_reason = "Erro: SL de venda deve estar acima da entrada."; return false; }

   // ── Account base ─────────────────────────────────────────────────
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
     { out_reason = "Erro: saldo da conta indisponível."; return false; }
   double risk_money = balance * g_state.risk_percent / 100.0;
   if(risk_money <= 0.0)
     { out_reason = "Erro: percentual de risco resulta em valor zero."; return false; }

   // ── Core formula ──────────────────────────────────────────────────
   double pnl_per_lot = 0.0;
   if(!CalcSymbolPnLForMove(entry_price, sl_price, 1.0, is_buy, pnl_per_lot, out_reason))
      return false;

   double loss_per_lot = MathAbs(pnl_per_lot) + CalcRoundTripCommissionMoney(1.0);
   if(loss_per_lot <= 0.0)
     { out_reason = "Erro: custo por lote calculado como zero."; return false; }

   double raw_lots = risk_money / loss_per_lot;

   // ── Normalize to broker constraints ───────────────────────────────
   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vol_min  <= 0.0) vol_min  = 0.01;
   if(vol_max  <= 0.0) vol_max  = 100.0;
   if(vol_step <= 0.0) vol_step = 0.01;

   // Floor to step boundary (conservative — do not exceed risk target)
   double steps     = MathFloor(raw_lots / vol_step);
   double norm_lots = NormalizeDouble(steps * vol_step, VolumeDigits());

   // ── Below broker minimum → fail cleanly; do NOT promote upward ───
   // Clamping up to vol_min would silently increase the trader's risk.
   if(norm_lots < vol_min)
     {
      out_reason = StringFormat(
         "Erro: risco muito baixo para o lote mínimo do símbolo (calculado %s, mínimo %s).",
         FormatLots(norm_lots), FormatLots(vol_min));
      return false;
     }

   // Cap downward at vol_max (conservative — never exceed broker cap)
   if(norm_lots > vol_max) norm_lots = NormalizeDouble(vol_max, VolumeDigits());

   out_lots = norm_lots;
   return (out_lots > 0.0);
  }

//+------------------------------------------------------------------+
//|  BuildTradePlan                                                  |
//|                                                                  |
//|  Builds a complete TradeParams from current g_state.             |
//|  Centralises all derivation: entry, SL, TP, lots, money, RR.    |
//|  Does NOT validate — call ValidateTradeRequest afterwards.       |
//+------------------------------------------------------------------+

bool BuildTradePlan(TradeParams &params, string &out_reason)
  {
   params.Clear();
   out_reason = "";

   if(g_state.action == ACTION_NONE)
     { out_reason = "Nenhuma ação selecionada."; return false; }

   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);

   // ── 1. Effective entry price ──────────────────────────────────────
   double entry = EffectiveStateEntryPrice(g_state.action);

   if(entry <= 0.0)
     { out_reason = "Preço de entrada indisponível."; return false; }
   params.entry_price = NormalizePriceValue(entry);

   if(is_market)
      SyncMarketPointsFromAbsoluteTargets(params.entry_price);

   // ── 2. SL / TP prices from effective state ───────────────────────
   params.sl_price  = EffectiveStateSLPrice(g_state.action, params.entry_price);
   params.tp_price  = EffectiveStateTPPrice(g_state.action, params.entry_price);
   params.sl_points = (params.sl_price > 0.0)
                      ? MathMax(0.0, MathRound(MathAbs(params.entry_price - params.sl_price) / _Point))
                      : 0.0;
   params.tp_points = (params.tp_price > 0.0)
                      ? MathMax(0.0, MathRound(MathAbs(params.tp_price - params.entry_price) / _Point))
                      : 0.0;

   // ── 3. Lots ───────────────────────────────────────────────────────
   if(g_state.risk_mode == RISK_MODE_PERCENT)
     {
      double calc_lots;
      string calc_reason;
      if(!CalcLotsFromRiskPercent(params.entry_price, params.sl_price,
                                  is_buy, calc_lots, calc_reason))
        { out_reason = calc_reason; return false; }
      params.lots     = calc_lots;
      params.risk_pct = g_state.risk_percent;
     }
   else
     {
      params.lots     = g_state.lots;
      params.risk_pct = 0.0;
     }

   if(params.lots <= 0.0)
     { out_reason = "Lotes inválidos."; return false; }

   // ── 4. R:R ratio ─────────────────────────────────────────────────
   params.rr_ratio = (params.sl_points > 0.0 && params.tp_points > 0.0)
                     ? NormalizeDouble(params.tp_points / params.sl_points, 2)
                     : 0.0;

   // ── 5. Risk / Reward money ────────────────────────────────────────
   if(params.sl_points > 0.0)
     {
      double risk_money = 0.0;
      string money_reason;
      if(CalcNetRiskMoneyForMove(params.entry_price, params.sl_price, params.lots,
                                 is_buy, risk_money, money_reason))
         params.risk_money = NormalizeDouble(risk_money, 2);

      if(params.tp_points > 0.0)
        {
         double reward_money = 0.0;
         if(CalcNetRewardMoneyForMove(params.entry_price, params.tp_price, params.lots,
                                      is_buy, reward_money, money_reason))
            params.reward_money = NormalizeDouble(reward_money, 2);
        }

      if(g_state.risk_mode == RISK_MODE_LOTS)
        {
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(balance > 0.0)
           {
            params.risk_pct    = NormalizeDouble(params.risk_money   / balance * 100.0, 2);
            params.reward_pct  = NormalizeDouble(params.reward_money / balance * 100.0, 2);
           }
        }
      else
        {
         // risk-% mode: balance already known — derive reward_pct from reward_money
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(balance > 0.0 && params.reward_money > 0.0)
            params.reward_pct = NormalizeDouble(params.reward_money / balance * 100.0, 2);
        }
     }

   return true;
  }

//+------------------------------------------------------------------+
//|  ValidateTradeRequest                                            |
//|                                                                  |
//|  Validates a built TradeParams against symbol and semantic rules.|
//|  Returns true + ready message, or false + first blocking reason. |
//+------------------------------------------------------------------+

bool ValidateTradeRequest(const TradeParams &params, string &message)
  {
   message = "";

   // ── 1. Action selected ────────────────────────────────────────────
   if(g_state.action == ACTION_NONE)
     { message = "Erro: nenhuma ação selecionada."; return false; }

   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);

   // ── 2. Entry price ────────────────────────────────────────────────
   if(params.entry_price <= 0.0)
     { message = "Erro: preço de entrada inválido."; return false; }

   // Pending requires a user-defined entry
   if(IsPendingAction(g_state.action) && g_state.entry_price <= 0.0)
     { message = "Erro: entrada pendente não definida."; return false; }

   // ── 3. SL must be set and non-zero ────────────────────────────────
   if(params.sl_points <= 0.0)
     { message = "Erro: distância de SL deve ser > 0."; return false; }
   if(params.sl_price <= 0.0)
     { message = "Erro: preço de SL inválido."; return false; }

   // ── 4. Semantic: SL on correct side of entry ──────────────────────
   if(is_buy && params.sl_price >= params.entry_price)
     { message = "Erro: SL de compra deve estar abaixo da entrada."; return false; }
   if(!is_buy && params.sl_price <= params.entry_price)
     { message = "Erro: SL de venda deve estar acima da entrada."; return false; }

   // ── 5. TP semantic (only if TP is set) ───────────────────────────
   if(params.tp_points > 0.0 && params.tp_price > 0.0)
     {
      if(is_buy && params.tp_price <= params.entry_price)
        { message = "Erro: TP de compra deve estar acima da entrada."; return false; }
      if(!is_buy && params.tp_price >= params.entry_price)
        { message = "Erro: TP de venda deve estar abaixo da entrada."; return false; }
     }

   // ── 6. Lots ───────────────────────────────────────────────────────
   if(params.lots <= 0.0)
     { message = "Erro: lotes devem ser > 0."; return false; }

   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(vol_min > 0.0 && params.lots < vol_min)
     { message = StringFormat("Erro: lotes %.5f abaixo do mínimo %.5f.", params.lots, vol_min); return false; }
   if(vol_max > 0.0 && params.lots > vol_max)
     { message = StringFormat("Erro: lotes %.5f acima do máximo %.5f.", params.lots, vol_max); return false; }

   // ── 7. Stops-level distance ───────────────────────────────────────
   // SYMBOL_TRADE_STOPS_LEVEL is in points (integer).
   int stops_level_pts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stops_level_pts > 0)
     {
      double min_dist = stops_level_pts * _Point;

      // For market orders the reference is current bid/ask.
      // For pending orders the reference is the entry price itself.
      // We check SL distance from entry (always required):
      double sl_dist = MathAbs(params.entry_price - params.sl_price);
      if(sl_dist < min_dist)
        {
         message = StringFormat("Erro: SL muito próximo (mínimo %d pontos, atual %.0f).",
                                stops_level_pts,
                                MathRound(sl_dist / _Point));
         return false;
        }

      // For pending orders also check entry distance from current price:
      if(IsPendingAction(g_state.action))
        {
         MqlTick tick;
         if(SymbolInfoTick(_Symbol, tick))
           {
            double ref_price  = is_buy ? tick.ask : tick.bid;
            double entry_dist = MathAbs(params.entry_price - ref_price);
            if(entry_dist < min_dist)
              {
               message = StringFormat("Erro: entrada pendente muito próxima do preço atual (mínimo %d pontos).",
                                      stops_level_pts);
               return false;
              }
           }
        }

      // TP distance check (if TP set):
      if(params.tp_points > 0.0 && params.tp_price > 0.0)
        {
         double tp_dist = MathAbs(params.entry_price - params.tp_price);
         if(tp_dist < min_dist)
           {
            message = StringFormat("Erro: TP muito próximo (mínimo %d pontos, atual %.0f).",
                                   stops_level_pts,
                                   MathRound(tp_dist / _Point));
            return false;
           }
        }
     }

   // ── 8. Freeze level (additional broker constraint) ────────────────
   int freeze_level_pts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if(freeze_level_pts > 0 && IsPendingAction(g_state.action))
     {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
        {
         double ref_price  = is_buy ? tick.ask : tick.bid;
         double entry_dist = MathAbs(params.entry_price - ref_price);
         double freeze_dist = freeze_level_pts * _Point;
         if(entry_dist < freeze_dist)
           {
            message = StringFormat("Aviso: entrada dentro da zona de freeze do broker (%d pontos).",
                                   freeze_level_pts);
            // This is a warning but still treat as blocking for safety:
            return false;
           }
        }
     }

   // ── All checks passed ─────────────────────────────────────────────
   string action_lbl = EffectiveActionLabel(g_state.action, params.entry_price);

   // lots_origin: show risk% and money when in percent mode
   string lots_origin = "";
   if(g_state.risk_mode == RISK_MODE_PERCENT && params.risk_pct > 0.0)
      lots_origin = StringFormat(" [%.2f%%=$%.2f]", params.risk_pct, params.risk_money);

   // TP field: price + points, or "sem TP"
   string tp_str = (params.tp_price > 0.0)
                   ? StringFormat(", TP %s (%.0f pt)", FormatPrice(params.tp_price), params.tp_points)
                   : ", sem TP";

   message = StringFormat("Pronto: %s, %s lots%s, entrada %s, SL %s (%.0f pt)%s",
                          action_lbl,
                          FormatLots(params.lots), lots_origin,
                          FormatPrice(params.entry_price),
                          FormatPrice(params.sl_price), params.sl_points,
                          tp_str);
   return true;
  }

//+------------------------------------------------------------------+
//|  ClearTradeDraftAfterSuccessfulSend                               |
//|  Desmonta o esboço da operação sem apagar a mensagem de sucesso.  |
//|  Chamado exclusivamente no ramo de sucesso real do Send.          |
//+------------------------------------------------------------------+

void ClearTradeDraftAfterSuccessfulSend()
  {
   g_state.action      = ACTION_NONE;
   g_state.entry_price = 0.0;
   ClearMarketPriceTargets();
   g_state.active_edit = EDIT_TARGET_NONE;
   // Não tocar no status — a mensagem de sucesso permanece visível
  }

//+------------------------------------------------------------------+
//|  SendSelectedOrder — FASE 4C: hardened real trade execution       |
//|                                                                  |
//|  Receives the plan already built and validated by the caller.    |
//|  Does NOT call BuildTradePlan or ValidateTradeRequest again —    |
//|  the caller owns the single build/validate cycle.               |
//|                                                                  |
//|  Safety gates ported from Position Sizer Trading.mqh:            |
//|    1. TERMINAL_CONNECTED                                         |
//|    2. TERMINAL_TRADE_ALLOWED                                     |
//|    3. MQL_TRADE_ALLOWED                                          |
//|    4. ACCOUNT_TRADE_ALLOWED + ACCOUNT_TRADE_EXPERT               |
//|    5. SYMBOL_TRADE_MODE                                          |
//|                                                                  |
//|  Pre-dispatch failures are tagged [PRE-DISPATCH] in logs.        |
//|  Broker retcode failures are tagged [BROKER] in logs.            |
//|                                                                  |
//|  Dispatch rules:                                                 |
//|    ACTION_BUY          -> g_trade.Buy(...)                       |
//|    ACTION_SELL         -> g_trade.Sell(...)                       |
//|    ACTION_BUY_PENDING  -> BuyStop / BuyLimit (by subtype)        |
//|    ACTION_SELL_PENDING -> SellStop / SellLimit (by subtype)      |
//+------------------------------------------------------------------+

bool SendSelectedOrder(const TradeParams &plan)
  {
   PendingSubtype st = DerivePendingSubtype(g_state.action, plan.entry_price);
   string effective_type = EffectiveActionLabel(g_state.action, plan.entry_price);

   // ══════════════════════════════════════════════════════════════════
   //  PART A — Pre-dispatch safety gates (ported from Position Sizer)
   //  If any of these fail, we NEVER call CTrade.  The failure is
   //  categorised as [PRE-DISPATCH] so it is immediately clear that
   //  the request was never sent to the broker.
   // ══════════════════════════════════════════════════════════════════

   // 1. Terminal connected to broker server?
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      string reason = "Terminal desconectado do servidor.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // 2. Algo trading enabled globally in terminal? (AutoTrading button)
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      string reason = "Algo trading desabilitado no terminal (botão AutoTrading).";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // 3. This EA allowed to trade? (EA properties / "Allow Algo Trading")
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      string reason = "Algo trading desabilitado para este EA.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // 4. Account-level trading permission
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      string reason = "Conta não permite trading (ACCOUNT_TRADE_ALLOWED=false).";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      string reason = "Conta não permite trading por EAs (ACCOUNT_TRADE_EXPERT=false).";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // 5. Symbol trade mode — is trading allowed on this instrument?
   ENUM_SYMBOL_TRADE_MODE sym_mode =
      (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(sym_mode == SYMBOL_TRADE_MODE_DISABLED)
     {
      string reason = "Símbolo " + _Symbol + " está desabilitado para trading.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }
   if(sym_mode == SYMBOL_TRADE_MODE_CLOSEONLY)
     {
      string reason = "Símbolo " + _Symbol + " só permite fechar posições (close-only).";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }
   // SYMBOL_TRADE_MODE_LONGONLY / SHORTONLY quick-guards
   if(sym_mode == SYMBOL_TRADE_MODE_LONGONLY && !IsBuyAction(g_state.action))
     {
      string reason = _Symbol + " só permite operações Long.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }
   if(sym_mode == SYMBOL_TRADE_MODE_SHORTONLY && IsBuyAction(g_state.action))
     {
      string reason = _Symbol + " só permite operações Short.";
      Print("[PRE-DISPATCH] ", reason);
      SetStatus("✗ " + reason, true);
      return false;
     }

   // ══════════════════════════════════════════════════════════════════
   //  Pre-send diagnostics log (execution mode, filling)
   // ══════════════════════════════════════════════════════════════════

   ENUM_SYMBOL_TRADE_EXECUTION exec_mode =
      (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   Print("=== LotForge 4C — REAL SEND ===");
   Print("Action      : ", effective_type);
   Print("Symbol      : ", _Symbol,
         "  mode=", EnumToString(sym_mode),
         "  exec=", EnumToString(exec_mode));
   Print("Filling     : ", EnumToString((ENUM_ORDER_TYPE_FILLING)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE)));
   Print("Entry       : ", FormatPrice(plan.entry_price));
   Print("SL          : ", FormatPrice(plan.sl_price),
         "  (", FormatPoints(plan.sl_points), " pt)");
   Print("TP          : ", plan.tp_price > 0.0 ? FormatPrice(plan.tp_price) : "---",
         "  (", FormatPoints(plan.tp_points), " pt)");
   Print("Lots        : ", FormatLots(plan.lots));
   Print("Comment     : ", g_state.order_comment);

   // ══════════════════════════════════════════════════════════════════
   //  DISPATCH — all prechecks passed, send to broker
   // ══════════════════════════════════════════════════════════════════

   bool ok = false;

   switch(g_state.action)
     {
      case ACTION_BUY:
         ok = g_trade.Buy(plan.lots, _Symbol,
                          0.0,                  // market price
                          plan.sl_price,
                          plan.tp_price,
                          g_state.order_comment);
         break;

      case ACTION_SELL:
         ok = g_trade.Sell(plan.lots, _Symbol,
                           0.0,                 // market price
                           plan.sl_price,
                           plan.tp_price,
                           g_state.order_comment);
         break;

      case ACTION_BUY_PENDING:
         if(st == PENDING_STOP)
            ok = g_trade.BuyStop(plan.lots, plan.entry_price, _Symbol,
                                 plan.sl_price, plan.tp_price,
                                 ORDER_TIME_GTC, 0,
                                 g_state.order_comment);
         else
            ok = g_trade.BuyLimit(plan.lots, plan.entry_price, _Symbol,
                                  plan.sl_price, plan.tp_price,
                                  ORDER_TIME_GTC, 0,
                                  g_state.order_comment);
         break;

      case ACTION_SELL_PENDING:
         if(st == PENDING_STOP)
            ok = g_trade.SellStop(plan.lots, plan.entry_price, _Symbol,
                                  plan.sl_price, plan.tp_price,
                                  ORDER_TIME_GTC, 0,
                                  g_state.order_comment);
         else
            ok = g_trade.SellLimit(plan.lots, plan.entry_price, _Symbol,
                                   plan.sl_price, plan.tp_price,
                                   ORDER_TIME_GTC, 0,
                                   g_state.order_comment);
         break;

      default:
         Print("[PRE-DISPATCH] Ação desconhecida: ", g_state.action);
         SetStatus("Erro: ação desconhecida.", true);
         return false;
     }

   // ══════════════════════════════════════════════════════════════════
   //  BROKER FEEDBACK — request was sent; inspect retcode
   // ══════════════════════════════════════════════════════════════════

   uint   retcode      = g_trade.ResultRetcode();
   string retcode_desc = g_trade.ResultRetcodeDescription();
   ulong  result_order = g_trade.ResultOrder();
   ulong  result_deal  = g_trade.ResultDeal();

   Print("Retcode     : ", retcode, " — ", retcode_desc);
   if(result_order > 0) Print("Order ticket: ", result_order);
   if(result_deal  > 0) Print("Deal  ticket: ", result_deal);
   Print("================================");

   if(ok && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED))
     {
      // ── Success ────────────────────────────────────────────────────
      if(IsMarketAction(g_state.action))
        {
         string msg = StringFormat("✓ %s enviado — %s lots @ %s | ticket #%d",
                                   effective_type,
                                   FormatLots(plan.lots),
                                   FormatPrice(plan.entry_price),
                                   (int)result_order);
         if(result_deal > 0)
            msg += StringFormat(" deal #%d", (int)result_deal);
         SetStatus(msg, true);
        }
      else
        {
         SetStatus(StringFormat("✓ %s colocado — %s lots @ %s | ticket #%d",
                                effective_type,
                                FormatLots(plan.lots),
                                FormatPrice(plan.entry_price),
                                (int)result_order), true);
        }
      Print("[BROKER] Trade SUCCESS: ", g_state.status_text);
      // Desmontar esboço — a mensagem de sucesso já foi fixada antes desta chamada
      ClearTradeDraftAfterSuccessfulSend();
      return true;
     }
   else
     {
      // ── Broker rejection ───────────────────────────────────────────
      string fail_msg = StringFormat("✗ %s FALHOU — [%d] %s",
                                     effective_type,
                                     retcode, retcode_desc);
      SetStatus(fail_msg, true);
      Print("[BROKER] Trade FAILED: ", fail_msg);
      return false;
     }
  }
