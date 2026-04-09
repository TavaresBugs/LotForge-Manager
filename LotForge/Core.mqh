//+------------------------------------------------------------------+
//|  ██  IMPLEMENTAÇÕES — helpers básicos                            |
//+------------------------------------------------------------------+

string ObjName(const string suffix) { return PANEL_PREFIX + suffix; }

void TracePerfEvent(const string text)
  {
   if(PERF_TRACE_ENABLED)
      Print("[PERF] ", text);
  }

bool IsBuyAction(const TradePanelAction action)
  { return (action == ACTION_BUY || action == ACTION_BUY_PENDING); }

bool IsMarketAction(const TradePanelAction action)
  { return (action == ACTION_BUY || action == ACTION_SELL); }

bool IsPendingAction(const TradePanelAction action)
  { return (action == ACTION_BUY_PENDING || action == ACTION_SELL_PENDING); }

string ActionLabel(const TradePanelAction action)
  {
   switch(action)
     {
      case ACTION_BUY:          return "Buy";
      case ACTION_SELL:         return "Sell";
      case ACTION_BUY_PENDING:  return "Buy Pending";
      case ACTION_SELL_PENDING: return "Sell Pending";
      default:                  return "None";
     }
  }

PendingSubtype DerivePendingSubtype(const TradePanelAction action,
                                    const double entry_price)
  {
   if(!IsPendingAction(action) || entry_price <= 0.0) return PENDING_NONE;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return PENDING_LIMIT;
   if(action == ACTION_BUY_PENDING)
      return (entry_price > tick.ask) ? PENDING_STOP : PENDING_LIMIT;
   else
      return (entry_price < tick.bid) ? PENDING_STOP : PENDING_LIMIT;
  }

string PendingSubtypeLabel(const PendingSubtype subtype)
  {
   switch(subtype)
     {
      case PENDING_STOP:  return " (Stop)";
      case PENDING_LIMIT: return " (Limit)";
      default:            return "";
     }
  }

string EffectiveActionLabel(const TradePanelAction action,
                            const double entry_price)
  {
   if(!IsPendingAction(action)) return ActionLabel(action);
   PendingSubtype st = DerivePendingSubtype(action, entry_price);
   return ActionLabel(action) + PendingSubtypeLabel(st);
  }
//+------------------------------------------------------------------+
//|  ShortPreviewLabel — condensed label for overlay preview bars     |
//|  Pending actions: "Buy (Stop)" / "Sell (Limit)" instead of       |
//|  "Buy Pending (Stop)" — cleaner fit inside the narrow bar.        |
//+------------------------------------------------------------------+

string ShortPreviewLabel(const TradePanelAction action, const double entry_price)
  {
   if(!IsPendingAction(action)) return ActionLabel(action);
   PendingSubtype st = DerivePendingSubtype(action, entry_price);
   string base = IsBuyAction(action) ? "Buy" : "Sell";
   return base + PendingSubtypeLabel(st);
  }

//+------------------------------------------------------------------+
//|  Price / volume helpers                                          |
//+------------------------------------------------------------------+

bool RefreshSymbolRuntimeMetadata(const bool force)
  {
   ulong now_ms = (ulong)GetTickCount();
   if(!force &&
      g_symbol_metadata.valid &&
      g_symbol_metadata.symbol == _Symbol &&
      now_ms >= g_symbol_metadata.last_refresh_ms &&
      (now_ms - g_symbol_metadata.last_refresh_ms) < SYMBOL_METADATA_TTL_MS)
      return true;

   SymbolRuntimeMetadata next;
   next.Clear();
   next.symbol = _Symbol;

   long digits_raw       = 0;
   long stops_level_raw  = 0;
   long freeze_level_raw = 0;
   double volume_min_raw = 0.0;
   double volume_max_raw = 0.0;
   double volume_step_raw = 0.0;
   double tick_size_raw   = 0.0;

   bool ok = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS, digits_raw) &&
             SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, volume_min_raw) &&
             SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, volume_max_raw) &&
             SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, volume_step_raw) &&
             SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tick_size_raw) &&
             SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stops_level_raw) &&
             SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL, freeze_level_raw);
   if(!ok)
     {
      g_perf_symbol_metadata_refresh_failure_count++;
      TracePerfEvent("symbol metadata refresh failed");
      return (g_symbol_metadata.valid && g_symbol_metadata.symbol == _Symbol);
     }

   next.valid        = true;
   next.digits       = (digits_raw >= 0) ? (int)digits_raw : 5;
   next.volume_min   = (volume_min_raw > 0.0) ? volume_min_raw : 0.01;
   next.volume_max   = (volume_max_raw > 0.0) ? volume_max_raw : 100.0;
   next.volume_step  = (volume_step_raw > 0.0) ? volume_step_raw : 0.01;
   next.tick_size    = (tick_size_raw > 0.0) ? tick_size_raw : _Point;
   next.stops_level  = (stops_level_raw > 0) ? (int)stops_level_raw : 0;
   next.freeze_level = (freeze_level_raw > 0) ? (int)freeze_level_raw : 0;

   bool changed = (!g_symbol_metadata.valid ||
                   g_symbol_metadata.symbol       != next.symbol ||
                   g_symbol_metadata.digits       != next.digits ||
                   g_symbol_metadata.volume_min   != next.volume_min ||
                   g_symbol_metadata.volume_max   != next.volume_max ||
                   g_symbol_metadata.volume_step  != next.volume_step ||
                   g_symbol_metadata.tick_size    != next.tick_size ||
                   g_symbol_metadata.stops_level  != next.stops_level ||
                   g_symbol_metadata.freeze_level != next.freeze_level);
   next.revision = changed ? (g_symbol_metadata.revision + 1)
                           : g_symbol_metadata.revision;
   next.last_refresh_ms = now_ms;

   g_symbol_metadata = next;
   g_perf_symbol_metadata_refresh_count++;
   if(changed)
      TracePerfEvent("symbol metadata revision updated");
   return true;
  }

int SymbolDigitsCached()
  {
   if(g_symbol_metadata.valid &&
      g_symbol_metadata.symbol == _Symbol &&
      g_symbol_metadata.digits >= 0)
      return g_symbol_metadata.digits;

   if(RefreshSymbolRuntimeMetadata(true))
      return g_symbol_metadata.digits;

   long digits_raw = 0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS, digits_raw) && digits_raw >= 0)
      return (int)digits_raw;
   return 5;
  }

double SymbolVolumeMinCached()
  {
   if(g_symbol_metadata.valid &&
      g_symbol_metadata.symbol == _Symbol &&
      g_symbol_metadata.volume_min > 0.0)
      return g_symbol_metadata.volume_min;

   if(RefreshSymbolRuntimeMetadata(true))
      return g_symbol_metadata.volume_min;

   double value = 0.0;
   if(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, value) && value > 0.0)
      return value;
   return 0.01;
  }

double SymbolVolumeMaxCached()
  {
   if(g_symbol_metadata.valid &&
      g_symbol_metadata.symbol == _Symbol &&
      g_symbol_metadata.volume_max > 0.0)
      return g_symbol_metadata.volume_max;

   if(RefreshSymbolRuntimeMetadata(true))
      return g_symbol_metadata.volume_max;

   double value = 0.0;
   if(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, value) && value > 0.0)
      return value;
   return 100.0;
  }

double SymbolVolumeStepCached()
  {
   if(g_symbol_metadata.valid &&
      g_symbol_metadata.symbol == _Symbol &&
      g_symbol_metadata.volume_step > 0.0)
      return g_symbol_metadata.volume_step;

   if(RefreshSymbolRuntimeMetadata(true))
      return g_symbol_metadata.volume_step;

   double value = 0.0;
   if(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, value) && value > 0.0)
      return value;
   return 0.01;
  }

double SymbolTickSizeCached()
  {
   if(g_symbol_metadata.valid &&
      g_symbol_metadata.symbol == _Symbol &&
      g_symbol_metadata.tick_size > 0.0)
      return g_symbol_metadata.tick_size;

   if(RefreshSymbolRuntimeMetadata(true))
      return g_symbol_metadata.tick_size;

   double value = 0.0;
   if(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, value) && value > 0.0)
      return value;
   return _Point;
  }

int SymbolStopsLevelCached()
  {
   if(g_symbol_metadata.valid && g_symbol_metadata.symbol == _Symbol)
      return g_symbol_metadata.stops_level;

   if(RefreshSymbolRuntimeMetadata(true))
      return g_symbol_metadata.stops_level;

   long value = 0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, value) && value > 0)
      return (int)value;
   return 0;
  }

int SymbolFreezeLevelCached()
  {
   if(g_symbol_metadata.valid && g_symbol_metadata.symbol == _Symbol)
      return g_symbol_metadata.freeze_level;

   if(RefreshSymbolRuntimeMetadata(true))
      return g_symbol_metadata.freeze_level;

   long value = 0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL, value) && value > 0)
      return (int)value;
   return 0;
  }

ulong CurrentSymbolMetadataRevision()
  {
   return g_symbol_metadata.revision;
  }

int PriceDigits()
  {
   int d = SymbolDigitsCached();
   return (d < 0) ? 5 : d;
  }

int VolumeDigits()
  {
   double step = SymbolVolumeStepCached();
   if(step <= 0.0) return 2;
   int d = 0;
   double v = step;
   while(v < 1.0 - 1e-9) { v *= 10.0; d++; }
   return d;
  }

double NormalizePriceValue(const double price)
  { return NormalizeDouble(price, PriceDigits()); }

double NormalizeVolumeValue(const double volume)
  {
   double mn = SymbolVolumeMinCached();
   double mx = SymbolVolumeMaxCached();
   double st = SymbolVolumeStepCached();
   double v = MathMax(mn, MathMin(mx, MathRound(volume / st) * st));
   return NormalizeDouble(v, VolumeDigits());
  }

string FormatLots(const double volume)
  { return DoubleToString(volume, VolumeDigits()); }

string FormatPrice(const double price)
  { return DoubleToString(price, PriceDigits()); }

string FormatPoints(const double points)
  { return DoubleToString(points, 0); }

string FormatMoney(const double value)
  { return DoubleToString(value, 2); }

string FormatPercent(const double value)
  { return DoubleToString(value, 2) + "%"; }

double CurrentReferencePrice(const bool is_buy)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return 0.0;
   return is_buy ? tick.ask : tick.bid;
  }

double CurrentMidPrice()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return 0.0;
   return (tick.ask + tick.bid) * 0.5;
  }

bool ParseDoubleText(string text, double &value)
  {
   StringTrimLeft(text); StringTrimRight(text);
   if(StringLen(text) == 0) return false;
   value = StringToDouble(text);
   return true;
  }

void ClearMarketPriceTargets()
  {
   g_state.market_sl_price = 0.0;
   g_state.market_tp_price = 0.0;
  }

void ArmMarketPriceTargetsFromCurrentPoints()
  {
   if(!IsMarketAction(g_state.action))
     {
      ClearMarketPriceTargets();
      return;
     }

   bool is_buy = IsBuyAction(g_state.action);
   double entry_price = CurrentReferencePrice(is_buy);
   if(entry_price <= 0.0)
     {
      ClearMarketPriceTargets();
      return;
     }

   if(g_state.sl_points > 0.0)
      g_state.market_sl_price = NormalizePriceValue(
         is_buy ? entry_price - g_state.sl_points * _Point
                : entry_price + g_state.sl_points * _Point);
   else
      g_state.market_sl_price = 0.0;

   if(g_state.tp_points > 0.0)
      g_state.market_tp_price = NormalizePriceValue(
         is_buy ? entry_price + g_state.tp_points * _Point
                : entry_price - g_state.tp_points * _Point);
   else
      g_state.market_tp_price = 0.0;
  }

void SyncMarketPointsFromAbsoluteTargets(const double entry_price)
  {
   if(!IsMarketAction(g_state.action) || entry_price <= 0.0)
      return;

   if(g_state.market_sl_price > 0.0)
      g_state.sl_points = MathMax(0.0, MathRound(MathAbs(g_state.market_sl_price - entry_price) / _Point));
   if(g_state.market_tp_price > 0.0)
      g_state.tp_points = MathMax(0.0, MathRound(MathAbs(g_state.market_tp_price - entry_price) / _Point));
  }

double EffectiveStateEntryPrice(const TradePanelAction action)
  {
   if(IsMarketAction(action))
      return CurrentReferencePrice(IsBuyAction(action));
   return g_state.entry_price;
  }

double EffectiveStateSLPrice(const TradePanelAction action, const double entry_price)
  {
   if(entry_price <= 0.0)
      return 0.0;

   if(IsMarketAction(action) && g_state.market_sl_price > 0.0)
      return NormalizePriceValue(g_state.market_sl_price);

   if(g_state.sl_points <= 0.0)
      return 0.0;

   bool is_buy = IsBuyAction(action);
   return NormalizePriceValue(is_buy ? entry_price - g_state.sl_points * _Point
                                     : entry_price + g_state.sl_points * _Point);
  }

double EffectiveStateTPPrice(const TradePanelAction action, const double entry_price)
  {
   if(entry_price <= 0.0)
      return 0.0;

   if(IsMarketAction(action) && g_state.market_tp_price > 0.0)
      return NormalizePriceValue(g_state.market_tp_price);

   if(g_state.tp_points <= 0.0)
      return 0.0;

   bool is_buy = IsBuyAction(action);
   return NormalizePriceValue(is_buy ? entry_price + g_state.tp_points * _Point
                                     : entry_price - g_state.tp_points * _Point);
  }

//+------------------------------------------------------------------+
//|  SetStatus / EnsurePendingEntry                                  |
//+------------------------------------------------------------------+

void SetStatus(const string text, const bool sticky = false)
  {
   g_state.status_text = text;
   if(sticky) g_status_sticky = true;
   Print("[STATUS] ", text);
  }

void EnsurePendingEntry()
  {
   if(!IsPendingAction(g_state.action)) return;
   if(g_state.entry_price > 0.0) return;
   g_state.entry_price = CurrentReferencePrice(IsBuyAction(g_state.action));
  }

//+------------------------------------------------------------------+
//|  Save/restore scroll                                             |
//+------------------------------------------------------------------+

void SuppressChartScroll()
  {
   if(g_scroll_suppressed) return;
   g_scroll_was_enabled = (bool)ChartGetInteger(0, CHART_MOUSE_SCROLL);
   ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
   g_scroll_suppressed = true;
  }

void RestoreChartScroll()
  {
   if(!g_scroll_suppressed) return;
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_scroll_was_enabled);
   g_scroll_suppressed = false;
  }

void RequestChartRedraw()
  {
   g_chart_redraw_pending = true;
  }

void FlushPendingChartRedraw()
  {
   if(!g_chart_redraw_pending)
      return;
   ChartRedraw(0);
   g_chart_redraw_pending = false;
  }

void ResetDragState()
  {
   g_drag_phase     = DRAG_IDLE;
   g_drag_line_kind = "";
   g_drag_press_x   = 0;
   g_drag_press_y   = 0;
   g_native_preview_line_dragging = false;
   g_native_preview_line_kind     = "";
   g_panel_manual_dragging        = false;
   g_panel_edge_drag_candidate    = false;
   g_panel_edge_press_x           = 0;
   g_panel_edge_press_y           = 0;
   g_panel_edge_origin_x          = 0;
   g_panel_edge_origin_y          = 0;
   g_chart_redraw_pending         = false;
   RestoreChartScroll();
  }

//+------------------------------------------------------------------+
//|  DeletePreviewObjects / DeleteByPrefix                           |
//+------------------------------------------------------------------+

void InvalidatePreviewSnapshot()
  {
   g_preview_snapshot.Clear();
   g_preview_snapshot_ready = false;
   g_preview_dirty          = false;
   g_preview_market_entry_key = 0.0;
   g_preview_geometry_candle_count = 0;
   g_preview_geometry_bar_right    = 0;
  }

void InvalidatePreviewFinancialState()
  {
   g_preview_financial_key.Clear();
   g_preview_financial_state.Clear();
   g_preview_financial_dirty = false;
  }

void MarkPreviewFinancialDirty()
  {
   g_preview_financial_state.ready = false;
   g_preview_financial_dirty       = true;
  }

void MarkPreviewDirty()
  {
   g_preview_dirty = true;
   MarkPreviewFinancialDirty();
  }

bool ShouldRefreshPreviewOnPulse()
  {
   if(g_state.action == ACTION_NONE || !InpShowPreview)
      return false;

   if(g_preview_dirty ||
      g_preview_financial_dirty ||
      !g_preview_snapshot_ready ||
      !g_preview_snapshot.visible ||
      g_preview_snapshot.action != g_state.action)
      return true;

   if(!IsMarketAction(g_state.action))
      return false;

   double entry_price = EffectiveStateEntryPrice(g_state.action);
   if(entry_price <= 0.0)
      return false;

   double entry_key = NormalizePriceValue(entry_price);
   return (g_preview_market_entry_key <= 0.0 ||
           entry_key != g_preview_market_entry_key);
  }

void DeletePreviewObjects()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, PREV_PFX) == 0)
         ObjectDelete(0, n);
     }
   InvalidatePreviewSnapshot();
   InvalidatePreviewFinancialState();
   ResetDragState();
  }

void DeleteByPrefix()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, PANEL_PREFIX) == 0)
         ObjectDelete(0, n);
     }
  }
