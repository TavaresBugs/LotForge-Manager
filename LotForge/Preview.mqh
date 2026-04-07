//+------------------------------------------------------------------+
//|  ██  STEPPERS                                                    |
//+------------------------------------------------------------------+

void AdjustLots(const int direction)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   g_state.lots = NormalizeVolumeValue(g_state.lots + step * direction);
  }

void AdjustEntry(const int direction)
  {
   if(g_state.entry_price <= 0.0)
      g_state.entry_price = CurrentReferencePrice(IsBuyAction(g_state.action));
   if(g_state.entry_price <= 0.0) return;
   double step = InpEntryStepPoints * _Point;
   g_state.entry_price = NormalizePriceValue(g_state.entry_price + step * direction);
   if(g_state.entry_price < 0.0) g_state.entry_price = 0.0;
  }

void AdjustDistance(double &distance_points, const int direction)
  { distance_points = MathMax(0.0, distance_points + InpDistanceStepPoints * direction); }


//+------------------------------------------------------------------+
//|  ██  PREVIEW — ETAPA 3.5                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  EnsurePreviewLine — OBJ_HLINE para as três linhas horizontais   |
//+------------------------------------------------------------------+

void EnsurePreviewLine(const string kind,
                       const double price,
                       const color  clr,
                       const int    line_style,
                       const int    line_width,
                       const string tooltip)
  {
   string name = PREV_PFX + kind + "_line";
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, TimeCurrent(), price)) return;
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);   // native drag via CHARTEVENT_OBJECT_DRAG
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);  // foreground — clickable
     }
   ObjectSetDouble(0,  name, OBJPROP_PRICE,   price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,   line_style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   line_width);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, tooltip);
  }

//+------------------------------------------------------------------+
//|  PreviewCandleCount / CalcPreviewTimeRange                       |
//+------------------------------------------------------------------+

int PreviewCandleCount()
  {
   int scale = (int)ChartGetInteger(0, CHART_SCALE);
   switch(scale)
     {
      case 5:  return 8;
      case 4:  return 16;
      case 3:  return 32;
      case 2:  return 64;
      case 1:  return 128;
      default: return 256;
     }
  }

void CalcPreviewTimeRange(datetime &t1, datetime &t2)
  {
   int candles = PreviewCandleCount();

   // t2: right edge = open of the last fully-closed bar (shift 1).
   // Fallback chain: shift1 -> shift0 -> TimeCurrent().
   datetime bar_right = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(bar_right == 0) bar_right = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar_right == 0) bar_right = TimeCurrent();
   t2 = bar_right;

   // t1: left edge = open of the bar exactly 'candles' bars to the left of bar1.
   // bar1 is at shift=1 from bar0, so that bar is at shift = 1+candles.
   // Using real iTime() shifts means coverage tracks actual bars, not wall-clock
   // seconds — weekend/holiday gaps and TF changes never distort the range.
   datetime bar_left = iTime(_Symbol, PERIOD_CURRENT, 1 + candles);
   if(bar_left == 0)
      bar_left = bar_right - (datetime)((long)candles * PeriodSeconds()); // fallback
   t1 = bar_left;
  }

//+------------------------------------------------------------------+
//|  IsMouseOverPanel — delegates to g_panel                         |
//+------------------------------------------------------------------+

bool IsMouseOverPanel(const int mouse_x, const int mouse_y)
  {
   return g_panel.IsMouseOverPanel(mouse_x, mouse_y);
  }

//+------------------------------------------------------------------+
//|  Typography for all handle labels must stay fixed.               |
//|  No zoom-based font swap and no adaptive font shrink.            |
//|  When space is tight, we trim the text, not the font.            |
//+------------------------------------------------------------------+

void MeasureHandleLabelText(const string text, uint &tw, uint &th)
  {
   tw = 0;
   th = 0;
   TextSetFont("Arial Bold", -110);
   TextGetSize(text, tw, th);

   if(tw == 0 || th == 0)
     {
      tw = (uint)(StringLen(text) * OVL_FALLBACK_CHAR_W);
      th = (uint)OVL_FALLBACK_H;
     }
  }

string FitHandleLabelText(const string text, const int avail_w)
  {
   uint tw = 0, th = 0;
   MeasureHandleLabelText(text, tw, th);
   if((int)tw <= avail_w)
      return text;

   string suffix = "...";
   MeasureHandleLabelText(suffix, tw, th);
   if((int)tw > avail_w)
      return "";

   int len = StringLen(text);
   while(len > 0)
     {
      string clipped = StringSubstr(text, 0, len) + suffix;
      MeasureHandleLabelText(clipped, tw, th);
      if((int)tw <= avail_w)
         return clipped;
      len--;
     }

   return suffix;
  }

void ApplyHandleLabelFont(const string obj_name)
  {
   ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 11);
  }

//+------------------------------------------------------------------+
//|  ██  3.5: DrawPreviewZone — renderer principal                   |
//|                                                                  |
//|  Cria / atualiza dois objetos com o mesmo par (t1, t2):          |
//|    <kind>_zone  — OBJ_RECTANGLE preenchido (a zona de cor)       |
//|    <kind>_text  — OBJ_TEXT centralizado dentro da zona           |
//|                                                                  |
//|  Posicionamento do texto — 3.5b:                                 |
//|                                                                  |
//|  O texto fica COLADO À LINHA de referência de cada zona,         |
//|  não no centro da zona. Isso segue o mock:                       |
//|    TP text  → logo abaixo da linha do TP                         |
//|    Entry text → logo abaixo da linha de entry                    |
//|    SL text  → logo abaixo da linha do SL                         |
//|                                                                  |
//|  Parâmetro text_line_price: preço da linha de referência.        |
//|  ANCHOR_LEFT_UPPER: o ponto de ancoragem fica no canto superior  |
//|  esquerdo do glyph → texto cresce para baixo-direita a partir    |
//|  da linha. Isso posiciona o label "dentro da zona, logo abaixo   |
//|  da borda superior".                                             |
//|                                                                  |
//|  Horizontal: t_text = t1 + (t2-t1)/8, alinhado à esquerda da   |
//|  zona com pequena margem (igual ao mock da imagem 1).            |
//+------------------------------------------------------------------+

void DrawPreviewZone(const string   kind,
                     const datetime t1,
                     const datetime t2,
                     const double   price_hi,
                     const double   price_lo,
                     const color    fill_clr,
                     const color    border_clr,
                     const color    text_clr,
                     const string   label_text,
                     const double   text_line_price)   // preço da linha de referência
  {
   // ── Retângulo de fundo ────────────────────────────────────────────
   string rect_n = PREV_PFX + kind + "_zone";
   if(ObjectFind(0, rect_n) < 0)
     {
      if(!ObjectCreate(0, rect_n, OBJ_RECTANGLE, 0,
                       t1, price_hi, t2, price_lo)) return;
      ObjectSetInteger(0, rect_n, OBJPROP_FILL,       true);
      ObjectSetInteger(0, rect_n, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, rect_n, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, rect_n, OBJPROP_BACK,       true);
      ObjectSetInteger(0, rect_n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rect_n, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, rect_n, OBJPROP_HIDDEN,     false);
     }
   ObjectSetInteger(0, rect_n, OBJPROP_TIME,  0, t1);
   ObjectSetDouble(0,  rect_n, OBJPROP_PRICE, 0, price_hi);
   ObjectSetInteger(0, rect_n, OBJPROP_TIME,  1, t2);
   ObjectSetDouble(0,  rect_n, OBJPROP_PRICE, 1, price_lo);
   // OBJ_RECTANGLE com FILL=true: OBJPROP_COLOR = cor do preenchimento
   ObjectSetInteger(0, rect_n, OBJPROP_COLOR, fill_clr);

   // Chart-space OBJ_TEXT replaced by screen-space overlay labels.
   // UpdateOverlayPreviewLabel() is called from UpdatePreviewZones().
  }

//+------------------------------------------------------------------+
//|  ErasePreviewZone — remove zona + texto de um kind               |
//+------------------------------------------------------------------+

void ErasePreviewZone(const string kind)
  {
   string rect_n = PREV_PFX + kind + "_zone";
   string text_n = PREV_PFX + kind + "_text";
   if(ObjectFind(0, rect_n) >= 0) ObjectDelete(0, rect_n);
   if(ObjectFind(0, text_n) >= 0) ObjectDelete(0, text_n);
   EraseOverlayLabel(kind);   // also remove screen-space overlay pair
  }


//+------------------------------------------------------------------+
//|  EraseOverlayLabel — remove screen-space overlay pair for a kind |
//+------------------------------------------------------------------+

void EraseOverlayLabel(const string kind)
  {
   string bg_n  = PREV_PFX + kind + "_ovbg";
   string txt_n = PREV_PFX + kind + "_ovtxt";
   if(ObjectFind(0, bg_n)  >= 0) ObjectDelete(0, bg_n);
   if(ObjectFind(0, txt_n) >= 0) ObjectDelete(0, txt_n);
  }

//+------------------------------------------------------------------+
//|  UpdateOverlayPreviewLabel — Position-Sizer-style screen overlay  |
//|                                                                   |
//|  Creates / updates a right-edge-anchored OBJ_RECTANGLE_LABEL +   |
//|  OBJ_LABEL pair positioned from price via ChartTimePriceToXY.    |
//|  Both objects live in screen-space (CORNER_LEFT_UPPER +           |
//|  XDISTANCE/YDISTANCE), OBJPROP_BACK=false — floats above chart   |
//|  and can visually overlap the CAppDialog panel.                   |
//|                                                                   |
//|  Always recomputes layout from the current chart geometry/text.   |
//|  This avoids visual drift from cached width/height assumptions.   |
//+------------------------------------------------------------------+

void UpdateOverlayPreviewLabel(const string kind,
                               const string   text,
                               const double   price,
                               const datetime t1,
                               const datetime t2,
                               const bool     above_line,
                               const color    bg_clr,
                               const color    border_clr,
                               const color    txt_clr)
  {
   // ── Convert t1 / t2 to screen X ──────────────────────────────────
   int px1, px2, py1, py2;
   if(!ChartTimePriceToXY(0, 0, t1, price, px1, py1)) return;
   if(!ChartTimePriceToXY(0, 0, t2, price, px2, py2)) return;

   int bar_x = MathMin(px1, px2) - 2;
   int bar_w = MathAbs(px2 - px1) + 2;
   if(bar_w < 1) return;

   int py = py1;

   int box_h = OVL_BAR_H;
   int box_y;
   if(above_line)
      box_y = py - OVL_LINE_OFFSET - box_h;
   else
      box_y = py + OVL_LINE_OFFSET;

   string bg_n  = PREV_PFX + kind + "_ovbg";
   string txt_n = PREV_PFX + kind + "_ovtxt";

   bool bg_exists  = (ObjectFind(0, bg_n)  >= 0);
   bool txt_exists = (ObjectFind(0, txt_n) >= 0);
   int avail_w  = MathMax(10, bar_w - 2 * OVL_PAD_X);
   string fitted_text = FitHandleLabelText(text, avail_w);

   uint tw = 0, th = 0;
   MeasureHandleLabelText(fitted_text == "" ? " " : fitted_text, tw, th);

   int txt_x = bar_x + OVL_PAD_X;
   int txt_y = box_y + MathMax(1, (OVL_BAR_H - (int)th) / 2 - 1);

   // ── OBJ_RECTANGLE_LABEL ──────────────────────────────────────────
   if(!bg_exists)
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

   // ── OBJ_LABEL ────────────────────────────────────────────────────
   if(!txt_exists)
     {
      if(!ObjectCreate(0, txt_n, OBJ_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, txt_n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, txt_n, OBJPROP_HIDDEN,     false);
      ObjectSetInteger(0, txt_n, OBJPROP_BACK,       false);
      ObjectSetInteger(0, txt_n, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, txt_n, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
     }
   ApplyHandleLabelFont(txt_n);
   ObjectSetInteger(0, txt_n, OBJPROP_XDISTANCE, txt_x);
   ObjectSetInteger(0, txt_n, OBJPROP_YDISTANCE, txt_y);
   ObjectSetString(0,  txt_n, OBJPROP_TEXT,      fitted_text);
   ObjectSetInteger(0, txt_n, OBJPROP_COLOR,     txt_clr);
  }

//+------------------------------------------------------------------+
//|  ██  4A.1: UpdatePreviewZones — labels built from real plan      |
//|                                                                  |
//|  When plan_valid=true, labels use financial data from the plan:  |
//|    Entry: "Buy (Stop) <price> | Lots <lots>"   — side/subtype    |
//|    SL:    "SL <price> | -$<risk> | <risk_pct>%"                 |
//|    TP:    "TP <price> | +$<reward> | <gain_pct>%"               |
//|                                                                  |
//|  RR is never shown on overlay bars.                              |
//|  "Pending" is never shown in the Entry bar text.                 |
//|  When plan_valid=false, falls back to price-only labels —        |
//|  geometry is still drawn; only text is degraded.                 |
//+------------------------------------------------------------------+

void UpdatePreviewZones(const double   entry_price,
                        const double   sl_price,
                        const double   tp_price,
                        const datetime t1,
                        const datetime t2,
                        const TradeParams &plan,
                        const bool     plan_valid)
  {
   double band = ENTRY_BAND_HALF_PTS * _Point;

   bool is_buy = IsBuyAction(g_state.action);

   // ── zone_sep: align TP/SL inner edges with the entry band outer edges.
   //  Both the TP zone bottom and the SL zone top are set to entry ± band,
   //  which is the exact same outer boundary used by the entry band rectangle.
   //  This makes the three zones tile perfectly — no geometric overlap,
   //  no sub-pixel bleed, no visible gap.
   double zone_sep = band;   // = ENTRY_BAND_HALF_PTS * _Point

   // ── TP zone ───────────────────────────────────────────────────────
   if(tp_price > 0.0)
     {
      // Inner edge pulled one tick TOWARD TP so it does not share the
      // exact entry_price boundary with the SL rectangle below.
      double tp_hi, tp_lo;
      if(tp_price > entry_price)
        { tp_hi = tp_price; tp_lo = entry_price + zone_sep; }
      else
        { tp_hi = entry_price - zone_sep; tp_lo = tp_price; }

      string tp_lbl;
      if(plan_valid && plan.reward_money > 0.0)
        {
         tp_lbl = StringFormat("TP %s | +$%.2f",
                    FormatPrice(tp_price),
                    plan.reward_money);
         if(plan.reward_pct > 0.0)
            tp_lbl += StringFormat(" | %.2f%%", plan.reward_pct);
        }
      else
        {
         tp_lbl = "TP " + FormatPrice(tp_price);
        }

      DrawPreviewZone("tp", t1, t2, tp_hi, tp_lo,
                      CLR_PREV_TP_FILL, CLR_PREV_TP_BORDER,
                      CLR_PREV_TP_TEXT, tp_lbl, tp_price);
      // ── TP overlay bar: must sit OUTWARD from entry (away from the zone)
      //  BUY:  TP is above entry → outward = further UP  → bar ABOVE TP line → above_line=true
      //  SELL: TP is below entry → outward = further DOWN → bar BELOW TP line → above_line=false
      bool tp_bar_above = is_buy;   // true for BUY (bar above line), false for SELL (bar below line)
      UpdateOverlayPreviewLabel("tp", tp_lbl, tp_price, t1, t2,
                                tp_bar_above,
                                CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
     }
   else
     {
      ErasePreviewZone("tp");
      EraseOverlayLabel("tp");
     }

   // ── SL zone ───────────────────────────────────────────────────────
   if(sl_price > 0.0)
     {
      // Inner edge pulled one tick TOWARD SL — symmetric with TP fix above.
      double sl_hi, sl_lo;
      if(sl_price < entry_price)
        { sl_hi = entry_price - zone_sep; sl_lo = sl_price; }
      else
        { sl_hi = sl_price; sl_lo = entry_price + zone_sep; }

      string sl_lbl;
      if(plan_valid && plan.risk_money > 0.0)
        {
         sl_lbl = StringFormat("SL %s | -$%.2f",
                    FormatPrice(sl_price),
                    plan.risk_money);
         if(plan.risk_pct > 0.0)
            sl_lbl += StringFormat(" | %.2f%%", plan.risk_pct);
        }
      else
        {
         sl_lbl = "SL " + FormatPrice(sl_price);
        }

      DrawPreviewZone("sl", t1, t2, sl_hi, sl_lo,
                      CLR_PREV_SL_FILL, CLR_PREV_SL_BORDER,
                      CLR_PREV_SL_TEXT, sl_lbl, sl_price);
      // ── SL overlay bar: must sit OUTWARD from entry (away from the zone)
      //  BUY:  SL is below entry → outward = further DOWN → bar BELOW SL line → above_line=false
      //  SELL: SL is above entry → outward = further UP   → bar ABOVE SL line → above_line=true
      bool sl_bar_above = !is_buy;  // false for BUY (bar below line), true for SELL (bar above line)
      UpdateOverlayPreviewLabel("sl", sl_lbl, sl_price, t1, t2,
                                sl_bar_above,
                                CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
     }
   else
     {
      ErasePreviewZone("sl");
      EraseOverlayLabel("sl");
     }

   // ── Entry band ────────────────────────────────────────────────────
   {
    string effective_lbl = ShortPreviewLabel(g_state.action, entry_price);
    // Use plan lots when valid (risk-mode may have computed a different
    // lot count than g_state.lots); fall back to g_state.lots otherwise.
    string lots_str = plan_valid
                      ? FormatLots(plan.lots)
                      : FormatLots(g_state.lots);
    string en_lbl = effective_lbl + " " + FormatPrice(entry_price) +
                    " | Lots " + lots_str;

    DrawPreviewZone("en", t1, t2,
                    entry_price + band, entry_price - band,
                    CLR_PREV_EN_FILL, CLR_PREV_EN_BORDER,
                    CLR_PREV_EN_TEXT, en_lbl, entry_price);
    // ── Entry overlay bar: sits on the TRAILING side relative to direction
    //  BUY:  price moves up → entry bar sits BELOW the entry line → above_line=false
    //  SELL: price moves down → entry bar sits ABOVE the entry line → above_line=true
    bool en_bar_above = !is_buy;   // false for BUY (below entry line), true for SELL (above entry line)
    UpdateOverlayPreviewLabel("en", en_lbl, entry_price, t1, t2,
                              en_bar_above,
                              CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
   }
  }

void ForcePreviewLinesFlat()
  {
   // Lines are now SELECTABLE — deselect them after updates to
   // avoid leftover anchor dots from previous drag operations.
   string kinds[] = {"entry_line", "sl_line", "tp_line"};
   for(int i = 0; i < ArraySize(kinds); i++)
     {
      string n = PREV_PFX + kinds[i];
      if(ObjectFind(0, n) >= 0)
         ObjectSetInteger(0, n, OBJPROP_SELECTED, false);
     }
  }

//+------------------------------------------------------------------+
//|  ██  3.5: UpdatePreview — fluxo principal                        |
//|                                                                  |
//|  Ordem:                                                           |
//|  1. Guard de ação/preview.                                        |
//|  2. Calcula entry/SL/TP.                                          |
//|  3. CalcPreviewTimeRange → t1/t2 (compartilhados).               |
//|  4. EnsurePreviewLine para as três linhas horizontais.            |
//|  5. UpdatePreviewZones para os três blocos OBJ_RECTANGLE+TEXT.   |
//|                                                                  |
//|  Os labels da 3.4 (OBJ_TEXT com ANCHOR_RIGHT à borda t2) foram   |
//|  removidos. O texto agora está DENTRO das zonas (centrado).       |
//+------------------------------------------------------------------+

void UpdatePreview(const bool do_redraw)
  {
   if(g_state.action == ACTION_NONE || !InpShowPreview)
     {
      DeletePreviewObjects();
      return;
     }



   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);

   double entry_price = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
   if(entry_price <= 0.0)
     {
      DeletePreviewObjects();
      return;
     }

   double pt       = _Point;
   double sl_price = 0.0;
   double tp_price = 0.0;

   if(g_state.sl_points > 0.0)
      sl_price = NormalizePriceValue(is_buy ? entry_price - g_state.sl_points * pt
                                           : entry_price + g_state.sl_points * pt);
   if(g_state.tp_points > 0.0)
      tp_price = NormalizePriceValue(is_buy ? entry_price + g_state.tp_points * pt
                                           : entry_price - g_state.tp_points * pt);

   // ── Attempt real plan for financial labels ────────────────────────
   // Two-stage check: build must succeed AND validation must pass.
   // Geometry is drawn from raw g_state prices regardless (below).
   // Financial labels (risk $, reward $, %, RR) only appear when the
   // plan is fully valid — i.e. would not be rejected at Send time.
   TradeParams plan;
   string      build_reason;
   string      validate_msg;
   bool        plan_built = BuildTradePlan(plan, build_reason);
   bool        plan_valid = plan_built && ValidateTradeRequest(plan, validate_msg);

   // ── Shared time range ─────────────────────────────────────────────
   datetime t1, t2;
   CalcPreviewTimeRange(t1, t2);

   // ── Horizontal lines (drag handles) ──────────────────────────────
   string effective_lbl = EffectiveActionLabel(g_state.action, entry_price);
   EnsurePreviewLine("entry", entry_price,
                     CLR_ENTRY_LINE, STYLE_DASH, 1,
                     effective_lbl + " @ " + FormatPrice(entry_price));
   if(sl_price > 0.0)
      EnsurePreviewLine("sl", sl_price, CLR_SL_LINE, STYLE_DASH, 1,
                        "SL @ " + FormatPrice(sl_price));
   else
     {
      string sl_ln = PREV_PFX + "sl_line";
      if(ObjectFind(0, sl_ln) >= 0) ObjectDelete(0, sl_ln);
      EraseOverlayLabel("sl");
     }
   if(tp_price > 0.0)
      EnsurePreviewLine("tp", tp_price, CLR_TP_LINE, STYLE_DASH, 1,
                        "TP @ " + FormatPrice(tp_price));
   else
     {
      string tp_ln = PREV_PFX + "tp_line";
      if(ObjectFind(0, tp_ln) >= 0) ObjectDelete(0, tp_ln);
      EraseOverlayLabel("tp");
     }

   // ── Zone rectangles + financial text ─────────────────────────────
   UpdatePreviewZones(entry_price, sl_price, tp_price, t1, t2, plan, plan_valid);

   // ── Phase 4B: preview guidance must NOT overwrite sticky status ──
   if(!g_status_sticky)
     {
      if(IsPendingAction(g_state.action))
         SetStatus("Ação: " + effective_lbl + ". Configure e clique Send.");
     }

   if(do_redraw)
      ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//|  ██  3.4: DetectOverlayBarHit / ApplyLineDrag / HandleNativeLineDrag |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  ██  3.4: DetectOverlayBarHit — screen-space overlay bar hit test |
//|                                                                   |
//|  Tests only the OBJ_RECTANGLE_LABEL overlay bars for mouse hits.  |
//|  Thin OBJ_HLINE proximity is no longer needed because lines are   |
//|  SELECTABLE and the MT5 engine handles their drag natively.       |
//+------------------------------------------------------------------+

string DetectOverlayBarHit(const int mx, const int my)
  {
   if(IsMouseOverPanel(mx, my)) return "";

   bool   is_buy    = IsBuyAction(g_state.action);
   bool   is_market = IsMarketAction(g_state.action);
   double pt        = _Point;

   double entry_p = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
   double sl_p    = 0.0;
   double tp_p    = 0.0;

   if(entry_p > 0.0)
     {
      if(g_state.sl_points > 0.0)
         sl_p = NormalizePriceValue(is_buy ? entry_p - g_state.sl_points * pt
                                           : entry_p + g_state.sl_points * pt);
      if(g_state.tp_points > 0.0)
         tp_p = NormalizePriceValue(is_buy ? entry_p + g_state.tp_points * pt
                                           : entry_p - g_state.tp_points * pt);
     }

   // ── Overlay bar rectangles (large easy targets) ──────────────────
   {
    string _n; int _bx,_by,_bw,_bh;
    // entry bar (pending only)
    if(IsPendingAction(g_state.action) && entry_p > 0.0)
      {
       _n = PREV_PFX + "en_ovbg";
       if(ObjectFind(0,_n) >= 0)
         {
          _bx=(int)ObjectGetInteger(0,_n,OBJPROP_XDISTANCE);
          _by=(int)ObjectGetInteger(0,_n,OBJPROP_YDISTANCE);
          _bw=(int)ObjectGetInteger(0,_n,OBJPROP_XSIZE);
          _bh=(int)ObjectGetInteger(0,_n,OBJPROP_YSIZE);
          if(mx>=_bx && mx<=_bx+_bw && my>=_by && my<=_by+_bh) return "entry";
         }
      }
    // sl bar
    if(sl_p > 0.0)
      {
       _n = PREV_PFX + "sl_ovbg";
       if(ObjectFind(0,_n) >= 0)
         {
          _bx=(int)ObjectGetInteger(0,_n,OBJPROP_XDISTANCE);
          _by=(int)ObjectGetInteger(0,_n,OBJPROP_YDISTANCE);
          _bw=(int)ObjectGetInteger(0,_n,OBJPROP_XSIZE);
          _bh=(int)ObjectGetInteger(0,_n,OBJPROP_YSIZE);
          if(mx>=_bx && mx<=_bx+_bw && my>=_by && my<=_by+_bh) return "sl";
         }
      }
    // tp bar
    if(tp_p > 0.0)
      {
       _n = PREV_PFX + "tp_ovbg";
       if(ObjectFind(0,_n) >= 0)
         {
          _bx=(int)ObjectGetInteger(0,_n,OBJPROP_XDISTANCE);
          _by=(int)ObjectGetInteger(0,_n,OBJPROP_YDISTANCE);
          _bw=(int)ObjectGetInteger(0,_n,OBJPROP_XSIZE);
          _bh=(int)ObjectGetInteger(0,_n,OBJPROP_YSIZE);
          if(mx>=_bx && mx<=_bx+_bw && my>=_by && my<=_by+_bh) return "tp";
         }
      }
   }

   return "";
  }

void ApplyLineDrag(const int mx, const int my)
  {
   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);
   int      subwin;
   datetime t_dummy;
   double   new_price;
   if(!ChartXYToTimePrice(0, mx, my, subwin, t_dummy, new_price)) return;
   if(new_price <= 0.0) return;

   double tick_sz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   new_price = (tick_sz > 0.0)
               ? NormalizePriceValue(MathRound(new_price / tick_sz) * tick_sz)
               : NormalizePriceValue(new_price);

   if(g_drag_line_kind == "entry" && IsPendingAction(g_state.action))
     {
      // ── Keep SL/TP at their absolute prices when entry moves ────────
      double old_entry = g_state.entry_price;
      double pt = _Point;
      double old_sl_price = 0.0, old_tp_price = 0.0;
      if(old_entry > 0.0 && g_state.sl_points > 0.0)
         old_sl_price = is_buy ? old_entry - g_state.sl_points * pt
                               : old_entry + g_state.sl_points * pt;
      if(old_entry > 0.0 && g_state.tp_points > 0.0)
         old_tp_price = is_buy ? old_entry + g_state.tp_points * pt
                               : old_entry - g_state.tp_points * pt;

      g_state.entry_price = new_price;

      if(old_sl_price > 0.0 && new_price > 0.0)
        {
         double new_sl_pts = MathRound(MathAbs(old_sl_price - new_price) / _Point);
         if(new_sl_pts >= 1.0)
            g_state.sl_points = new_sl_pts;
        }
      if(old_tp_price > 0.0 && new_price > 0.0)
        {
         double new_tp_pts = MathRound(MathAbs(old_tp_price - new_price) / _Point);
         if(new_tp_pts >= 1.0)
            g_state.tp_points = new_tp_pts;
        }
     }
   else if(g_drag_line_kind == "sl")
     {
      double ref_e = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
      if(ref_e > 0.0)
        {
         double min_tick = (tick_sz > 0.0) ? tick_sz : _Point;
         bool ok = is_buy ? (new_price < ref_e) : (new_price > ref_e);
         if(!ok) new_price = NormalizePriceValue(is_buy ? ref_e - min_tick : ref_e + min_tick);
         g_state.sl_points = MathMax(1.0, MathRound(MathAbs(new_price - ref_e) / _Point));
        }
     }
   else if(g_drag_line_kind == "tp")
     {
      double ref_e = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
      if(ref_e > 0.0)
        {
         double min_tick = (tick_sz > 0.0) ? tick_sz : _Point;
         bool ok = is_buy ? (new_price > ref_e) : (new_price < ref_e);
         if(!ok) new_price = NormalizePriceValue(is_buy ? ref_e + min_tick : ref_e - min_tick);
         g_state.tp_points = MathMax(1.0, MathRound(MathAbs(new_price - ref_e) / _Point));
        }
     }
  }

//+------------------------------------------------------------------+
//|  ██  HandleNativeLineDrag — processes CHARTEVENT_OBJECT_DRAG      |
//|                                                                   |
//|  Position-Sizer pattern: the MT5 engine moves the OBJ_HLINE      |
//|  visually during drag.  When the user releases, this fires once.  |
//|  We read the new OBJPROP_PRICE and update g_state accordingly.    |
//|  No MOUSE_MOVE involvement → zero conflict with CAppDialog drag.  |
//+------------------------------------------------------------------+

void HandleNativeLineDrag(const string obj_name)
  {
   if(g_state.action == ACTION_NONE) return;

   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);

   double new_price = ObjectGetDouble(0, obj_name, OBJPROP_PRICE);
   if(new_price <= 0.0) return;

   double tick_sz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_sz > 0.0)
      new_price = NormalizePriceValue(MathRound(new_price / tick_sz) * tick_sz);
   else
      new_price = NormalizePriceValue(new_price);

   // ── Identify which line was dragged ──────────────────────────────
   string entry_ln = PREV_PFX + "entry_line";
   string sl_ln    = PREV_PFX + "sl_line";
   string tp_ln    = PREV_PFX + "tp_line";

   if(obj_name == entry_ln && IsPendingAction(g_state.action))
     {
      // ── Keep SL/TP at their absolute prices when entry moves ────────
      //  Compute old absolute SL/TP, set new entry, then recalc points.
      double old_entry = g_state.entry_price;
      double pt = _Point;
      double old_sl_price = 0.0, old_tp_price = 0.0;
      if(old_entry > 0.0 && g_state.sl_points > 0.0)
         old_sl_price = is_buy ? old_entry - g_state.sl_points * pt
                               : old_entry + g_state.sl_points * pt;
      if(old_entry > 0.0 && g_state.tp_points > 0.0)
         old_tp_price = is_buy ? old_entry + g_state.tp_points * pt
                               : old_entry - g_state.tp_points * pt;

      g_state.entry_price = new_price;

      // Recalc SL/TP points to keep absolute prices fixed
      if(old_sl_price > 0.0 && new_price > 0.0)
        {
         double new_sl_pts = MathRound(MathAbs(old_sl_price - new_price) / pt);
         if(new_sl_pts >= 1.0)
            g_state.sl_points = new_sl_pts;
        }
      if(old_tp_price > 0.0 && new_price > 0.0)
        {
         double new_tp_pts = MathRound(MathAbs(old_tp_price - new_price) / pt);
         if(new_tp_pts >= 1.0)
            g_state.tp_points = new_tp_pts;
        }
     }
   else if(obj_name == sl_ln)
     {
      double ref_e = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
      if(ref_e > 0.0)
        {
         double min_tick = (tick_sz > 0.0) ? tick_sz : _Point;
         bool ok = is_buy ? (new_price < ref_e) : (new_price > ref_e);
         if(!ok) new_price = NormalizePriceValue(is_buy ? ref_e - min_tick : ref_e + min_tick);
         g_state.sl_points = MathMax(1.0, MathRound(MathAbs(new_price - ref_e) / _Point));
        }
     }
   else if(obj_name == tp_ln)
     {
      double ref_e = is_market ? CurrentReferencePrice(is_buy) : g_state.entry_price;
      if(ref_e > 0.0)
        {
         double min_tick = (tick_sz > 0.0) ? tick_sz : _Point;
         bool ok = is_buy ? (new_price > ref_e) : (new_price < ref_e);
         if(!ok) new_price = NormalizePriceValue(is_buy ? ref_e + min_tick : ref_e - min_tick);
         g_state.tp_points = MathMax(1.0, MathRound(MathAbs(new_price - ref_e) / _Point));
        }
     }
   else
     {
      return;   // not one of our lines
     }

   // Deselect the line so it doesn't stay highlighted with anchor points
   ObjectSetInteger(0, obj_name, OBJPROP_SELECTED, false);

   g_panel.RefreshValues();
   UpdatePreview();
  }

//+------------------------------------------------------------------+
//|  ██  HandleMouseMoveDrag — overlay-bar drag only                  |
//|                                                                   |
//|  The main line drag is now handled natively via OBJECT_DRAG.      |
//|  This handler processes drag on the screen-space overlay bars     |
//|  (OBJ_RECTANGLE_LABEL) which are NOT selectable OBJ_HLINE        |
//|  objects.  Also provides hover cursor feedback.                   |
//|                                                                   |
//|  CRITICAL: Always checks IsMouseOverPanel FIRST to avoid the      |
//|  bug where dragging the panel also moves a line underneath.       |
//+------------------------------------------------------------------+

void HandleMouseMoveDrag(const long   mouse_x_l,
                         const double mouse_y_d,
                         const bool   btn_down)
  {
   int mx = (int)mouse_x_l;
   int my = (int)mouse_y_d;

   // ── Release: clean up any active overlay drag ────────────────────
   if(!btn_down)
     {
      if(g_drag_phase == DRAG_ACTIVE_LINE)
        {
         RestoreChartScroll();
         g_drag_phase     = DRAG_IDLE;
         g_drag_line_kind = "";
         if(g_state.action != ACTION_NONE) UpdatePreview();
        }
      else if(g_drag_phase == DRAG_CANDIDATE)
        {
         RestoreChartScroll();   // was suppressed at hit detection
         g_drag_phase     = DRAG_IDLE;
         g_drag_line_kind = "";
        }
      return;
     }

   // ── CRITICAL GUARD: if mouse is over the panel, never start a drag ──
   if(g_drag_phase == DRAG_IDLE && IsMouseOverPanel(mx, my))
      return;

   if(g_drag_phase == DRAG_IDLE)
     {
      // Only detect overlay bar hits (not thin lines — those use native drag)
      string hit = (g_state.action != ACTION_NONE && InpShowPreview)
                   ? DetectOverlayBarHit(mx, my) : "";
      if(hit != "")
        {
         SuppressChartScroll();   // suppress IMMEDIATELY — don't wait for threshold
         g_drag_phase     = DRAG_CANDIDATE;
         g_drag_line_kind = hit;
         g_drag_press_x   = mx;
         g_drag_press_y   = my;
        }
      return;
     }

   if(g_drag_phase == DRAG_CANDIDATE)
     {
      int dx = MathAbs(mx - g_drag_press_x);
      int dy = MathAbs(my - g_drag_press_y);
      if(dx + dy < DRAG_THRESHOLD_PX) return;
      // chart scroll already suppressed at hit detection
      g_drag_phase = DRAG_ACTIVE_LINE;
     }

   if(g_drag_phase == DRAG_ACTIVE_LINE)
     {
      ApplyLineDrag(mx, my);
      g_panel.RefreshValues();
      UpdatePreview();
      return;
     }
  }
