//+------------------------------------------------------------------+
//|  ██  IMPLEMENTAÇÕES — helpers básicos                            |
//+------------------------------------------------------------------+

string ObjName(const string suffix) { return PANEL_PREFIX + suffix; }

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

int PriceDigits()
  {
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (d < 0) ? 5 : d;
  }

int VolumeDigits()
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
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
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(mn <= 0.0) mn = 0.01;
   if(mx <= 0.0) mx = 100.0;
   if(st <= 0.0) st = 0.01;
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

void ResetDragState()
  {
   g_drag_phase     = DRAG_IDLE;
   g_drag_line_kind = "";
   g_drag_press_x   = 0;
   g_drag_press_y   = 0;
   RestoreChartScroll();
  }

//+------------------------------------------------------------------+
//|  DeletePreviewObjects / DeleteByPrefix                           |
//+------------------------------------------------------------------+

void DeletePreviewObjects()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, PREV_PFX) == 0)
         ObjectDelete(0, n);
     }
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

