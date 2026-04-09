//+------------------------------------------------------------------+
//|  ██  STEPPERS                                                    |
//+------------------------------------------------------------------+

void AdjustLots(const int direction)
  {
   double step = SymbolVolumeStepCached();
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

bool IsPreviewLineUnderNativeDrag(const string kind)
  {
   return (g_native_preview_line_dragging && g_native_preview_line_kind == kind);
  }

bool PreviewLinePriceMoved(const string kind, const double expected_price)
  {
   if(expected_price <= 0.0)
      return false;

   string name = PREV_PFX + kind + "_line";
   if(ObjectFind(0, name) < 0)
      return false;
   if(!ObjectGetInteger(0, name, OBJPROP_SELECTED))
      return false;

   double live_price = ObjectGetDouble(0, name, OBJPROP_PRICE);
   if(live_price <= 0.0)
      return false;

   double tol = SymbolTickSizeCached();

   return (MathAbs(live_price - expected_price) > tol * 0.5);
  }

void RefreshNativePreviewLineDragState(const bool btn_down)
  {
   if(!btn_down || g_state.action == ACTION_NONE || !InpShowPreview)
     {
      g_native_preview_line_dragging = false;
      g_native_preview_line_kind     = "";
      return;
     }

   double entry_price = EffectiveStateEntryPrice(g_state.action);
   double sl_price    = EffectiveStateSLPrice(g_state.action, entry_price);
   double tp_price    = EffectiveStateTPPrice(g_state.action, entry_price);

   string moved_kind = "";
   if(IsPendingAction(g_state.action) && PreviewLinePriceMoved("entry", entry_price))
      moved_kind = "entry";
   else if(PreviewLinePriceMoved("sl", sl_price))
      moved_kind = "sl";
   else if(PreviewLinePriceMoved("tp", tp_price))
      moved_kind = "tp";

   g_native_preview_line_dragging = (moved_kind != "");
   g_native_preview_line_kind     = moved_kind;
  }

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
     }
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);   // behave like chart guide, behind panel/overlay
   bool selectable = (kind != "entry" || IsPendingAction(g_state.action));
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, selectable);   // native drag via CHARTEVENT_OBJECT_DRAG
   if(!selectable)
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   if(!IsPreviewLineUnderNativeDrag(kind))
      ObjectSetDouble(0,  name, OBJPROP_PRICE, price);
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

datetime CurrentPreviewBarRightTime()
  {
   datetime bar_right = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(bar_right == 0) bar_right = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar_right == 0) bar_right = TimeCurrent();
   return bar_right;
  }

//+------------------------------------------------------------------+
//|  IsMouseOverPanel — delegates to g_panel                         |
//+------------------------------------------------------------------+

bool IsMouseOverPanel(const int mouse_x, const int mouse_y)
  {
   return g_panel.IsMouseOverPanel(mouse_x, mouse_y);
  }

bool IsMouseNearPanel(const int mouse_x, const int mouse_y)
  {
   return g_panel.IsMouseNearPanel(mouse_x, mouse_y);
  }

void UpdatePanelScrollCapture(const int mouse_x, const int mouse_y)
  {
   bool want_capture = (g_panel_dragging ||
                        g_panel_manual_dragging ||
                        g_state.edit_in_progress ||
                        IsMouseNearPanel(mouse_x, mouse_y));
   if(want_capture)
     {
      SuppressChartScroll();
      return;
     }

   if(g_drag_phase == DRAG_IDLE && !g_native_preview_line_dragging)
      RestoreChartScroll();
  }

bool IsMouseInPanelEdgeGrabBand(const int mouse_x, const int mouse_y)
  {
   int x1 = (int)g_panel.Left();
   int y1 = (int)g_panel.Top();
   int x2 = (int)g_panel.Right();
   int y2 = (int)g_panel.Bottom();

   const int inside_band = 4;

   bool left_band = (mouse_x >= x1 - PANEL_PROXIMITY_PX &&
                     mouse_x <= x1 + inside_band &&
                     mouse_y >= y1 - PANEL_PROXIMITY_PX &&
                     mouse_y <= y2 + PANEL_PROXIMITY_PX);

   bool right_band = (mouse_x >= x2 - inside_band &&
                      mouse_x <= x2 + PANEL_PROXIMITY_PX &&
                      mouse_y >= y1 - PANEL_PROXIMITY_PX &&
                      mouse_y <= y2 + PANEL_PROXIMITY_PX);

   bool bottom_band = (mouse_x >= x1 - PANEL_PROXIMITY_PX &&
                       mouse_x <= x2 + PANEL_PROXIMITY_PX &&
                       mouse_y >= y2 - inside_band &&
                       mouse_y <= y2 + PANEL_PROXIMITY_PX);

   return (left_band || right_band || bottom_band);
  }

void ClampPanelPositionToChart(int &x, int &y)
  {
   int chart_w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chart_h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int panel_w = (int)g_panel.Width();
   int panel_h = (int)g_panel.Height();

   int max_x = MathMax(0, chart_w - panel_w);
   int max_y = MathMax(0, chart_h - panel_h);

   x = MathMax(0, MathMin(max_x, x));
   y = MathMax(0, MathMin(max_y, y));
  }

bool HandlePanelEdgeGrabDrag(const int mx, const int my, const bool btn_down)
  {
   if(g_panel_dragging)
      return false;

   if(!btn_down)
     {
      bool was_manual = g_panel_manual_dragging;
      g_panel_edge_drag_candidate = false;

      if(!was_manual)
         return false;

      g_panel_manual_dragging = false;
      SyncUiInteractionState();
      g_panel.RememberPanelState();
      if(g_state.action != ACTION_NONE)
         UpdatePreviewGeometryOnly();
      if(!RefreshManagedTradeMarkersGeometryOnly())
         RefreshAllManagedTradeMarkers();
      return true;
     }

   if(g_native_preview_line_dragging || g_drag_phase != DRAG_IDLE || g_state.edit_in_progress)
      return false;

   if(!g_panel_manual_dragging && !g_panel_edge_drag_candidate)
     {
      if(!IsMouseInPanelEdgeGrabBand(mx, my))
         return false;

      g_panel_edge_drag_candidate = true;
      g_panel_edge_press_x        = mx;
      g_panel_edge_press_y        = my;
      g_panel_edge_origin_x       = (int)g_panel.Left();
      g_panel_edge_origin_y       = (int)g_panel.Top();
      SuppressChartScroll();
      return true;
     }

   if(g_panel_edge_drag_candidate && !g_panel_manual_dragging)
     {
      int dx = MathAbs(mx - g_panel_edge_press_x);
      int dy = MathAbs(my - g_panel_edge_press_y);
      if(dx + dy < DRAG_THRESHOLD_PX)
         return true;

      g_panel_manual_dragging = true;
      SyncUiInteractionState();
      g_panel.BringPanelToFront();
     }

   if(!g_panel_manual_dragging)
      return false;

   int new_x = g_panel_edge_origin_x + (mx - g_panel_edge_press_x);
   int new_y = g_panel_edge_origin_y + (my - g_panel_edge_press_y);
   ClampPanelPositionToChart(new_x, new_y);
   g_panel.Move(new_x, new_y);
   return true;
  }

//+------------------------------------------------------------------+
//|  Typography for all handle labels must stay fixed.               |
//|  No zoom-based font swap and no adaptive font shrink.            |
//|  When space is tight, we trim the text, not the font.            |
//+------------------------------------------------------------------+

void EnsureHandleLabelMeasureFont()
  {
   if(g_handle_text_font_ready)
      return;
   TextSetFont("Arial Bold", -110);
   g_handle_text_font_ready = true;
  }

void MeasureHandleLabelText(const string text, uint &tw, uint &th)
  {
   for(int i = 0; i < HANDLE_TEXT_MEASURE_CACHE_SIZE; i++)
     {
      if(g_handle_text_measure_cache[i].valid &&
         g_handle_text_measure_cache[i].text == text)
        {
         tw = g_handle_text_measure_cache[i].width;
         th = g_handle_text_measure_cache[i].height;
         return;
        }
     }

   tw = 0;
   th = 0;
   EnsureHandleLabelMeasureFont();
   TextGetSize(text, tw, th);

   if(tw == 0 || th == 0)
     {
      tw = (uint)(StringLen(text) * OVL_FALLBACK_CHAR_W);
      th = (uint)OVL_FALLBACK_H;
     }

   int slot = g_handle_text_measure_cache_next;
   g_handle_text_measure_cache[slot].valid  = true;
   g_handle_text_measure_cache[slot].text   = text;
   g_handle_text_measure_cache[slot].width  = tw;
   g_handle_text_measure_cache[slot].height = th;
   g_handle_text_measure_cache_next++;
   if(g_handle_text_measure_cache_next >= HANDLE_TEXT_MEASURE_CACHE_SIZE)
      g_handle_text_measure_cache_next = 0;
  }

void FitHandleLabelText(const string text, const int avail_w,
                        string &fitted_text, uint &tw, uint &th)
  {
   for(int i = 0; i < HANDLE_TEXT_FIT_CACHE_SIZE; i++)
     {
      if(g_handle_text_fit_cache[i].valid &&
         g_handle_text_fit_cache[i].avail_w == avail_w &&
         g_handle_text_fit_cache[i].text == text)
        {
         fitted_text = g_handle_text_fit_cache[i].fitted_text;
         tw          = g_handle_text_fit_cache[i].width;
         th          = g_handle_text_fit_cache[i].height;
         return;
        }
     }

   MeasureHandleLabelText(text, tw, th);
   if((int)tw <= avail_w)
      fitted_text = text;
   else
     {
      string suffix = "...";
      MeasureHandleLabelText(suffix, tw, th);
      if((int)tw > avail_w)
         fitted_text = "";
      else
        {
         int len = StringLen(text);
         fitted_text = suffix;
         while(len > 0)
           {
            string clipped = StringSubstr(text, 0, len) + suffix;
            MeasureHandleLabelText(clipped, tw, th);
            if((int)tw <= avail_w)
              {
               fitted_text = clipped;
               break;
              }
            len--;
           }
        }
     }

   MeasureHandleLabelText(fitted_text == "" ? " " : fitted_text, tw, th);

   int slot = g_handle_text_fit_cache_next;
   g_handle_text_fit_cache[slot].valid       = true;
   g_handle_text_fit_cache[slot].text        = text;
   g_handle_text_fit_cache[slot].avail_w     = avail_w;
   g_handle_text_fit_cache[slot].fitted_text = fitted_text;
   g_handle_text_fit_cache[slot].width       = tw;
   g_handle_text_fit_cache[slot].height      = th;
   g_handle_text_fit_cache_next++;
   if(g_handle_text_fit_cache_next >= HANDLE_TEXT_FIT_CACHE_SIZE)
      g_handle_text_fit_cache_next = 0;
  }

void ApplyHandleLabelFont(const string obj_name)
  {
   ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 11);
  }

void ExpandOverlayBarToFitText(int &bar_x, int &bar_w, const string text)
  {
   uint tw = 0, th = 0;
   MeasureHandleLabelText(text, tw, th);

   int required_w = (int)tw + 2 * OVL_PAD_X + 2;
   if(required_w > bar_w)
      bar_w = required_w;
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
   bool bg_exists  = (ObjectFind(0, bg_n)  >= 0);
   bool txt_exists = (ObjectFind(0, txt_n) >= 0);
   if(bg_exists)  ObjectDelete(0, bg_n);
   if(txt_exists) ObjectDelete(0, txt_n);
  }

//+------------------------------------------------------------------+
//|  UpdateOverlayPreviewLabel — Position-Sizer-style screen overlay  |
//|                                                                   |
//|  Creates / updates a right-edge-anchored OBJ_RECTANGLE_LABEL +   |
//|  OBJ_LABEL pair positioned from price via ChartTimePriceToXY.    |
//|  Both objects live in screen-space (CORNER_LEFT_UPPER +           |
//|  XDISTANCE/YDISTANCE), OBJPROP_BACK=false — floats above chart   |
//|  and may render over the menu if geometry overlaps.               |
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
   ExpandOverlayBarToFitText(bar_x, bar_w, text);
   int avail_w  = MathMax(10, bar_w - 2 * OVL_PAD_X);
   string fitted_text;
   uint tw = 0, th = 0;
   FitHandleLabelText(text, avail_w, fitted_text, tw, th);

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
      ApplyHandleLabelFont(txt_n);
     }
   ObjectSetInteger(0, txt_n, OBJPROP_XDISTANCE, txt_x);
   ObjectSetInteger(0, txt_n, OBJPROP_YDISTANCE, txt_y);
   ObjectSetString(0,  txt_n, OBJPROP_TEXT,      fitted_text);
   ObjectSetInteger(0, txt_n, OBJPROP_COLOR,     txt_clr);
  }

void UpdateOverlayPreviewLabelsFromSnapshot(const PreviewSnapshot &snapshot,
                                            const datetime        t1,
                                            const datetime        t2)
  {
   double entry_price = snapshot.entry_price;
   double sl_price    = snapshot.sl_price;
   double tp_price    = snapshot.tp_price;

   if(tp_price > 0.0)
     {
      bool tp_bar_above = snapshot.is_buy;
      UpdateOverlayPreviewLabel("tp", snapshot.tp_label, tp_price, t1, t2,
                                tp_bar_above,
                                CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
     }
   else
      EraseOverlayLabel("tp");

   if(sl_price > 0.0)
     {
      bool sl_bar_above = !snapshot.is_buy;
      UpdateOverlayPreviewLabel("sl", snapshot.sl_label, sl_price, t1, t2,
                                sl_bar_above,
                                CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
     }
   else
      EraseOverlayLabel("sl");

   bool en_bar_above = !snapshot.is_buy;
   UpdateOverlayPreviewLabel("en", snapshot.en_label, entry_price, t1, t2,
                             en_bar_above,
                             CLR_OVL_HANDLE_BG, C'160,160,160', clrBlack);
  }

void RememberPreviewGeometryState(const datetime bar_right)
  {
   g_preview_geometry_candle_count = PreviewCandleCount();
   g_preview_geometry_bar_right    = bar_right;
  }

bool CanUseOverlayOnlyPreviewRefresh()
  {
   if(!g_preview_snapshot_ready || !g_preview_snapshot.visible)
      return false;

   if(g_preview_geometry_candle_count <= 0 || g_preview_geometry_bar_right <= 0)
      return false;

   if(PreviewCandleCount() != g_preview_geometry_candle_count)
      return false;

   return (CurrentPreviewBarRightTime() == g_preview_geometry_bar_right);
  }

bool PreviewFinancialKeysMatch(const PreviewFinancialKey &lhs,
                               const PreviewFinancialKey &rhs)
  {
   return (lhs.valid &&
           rhs.valid &&
           lhs.action            == rhs.action &&
           lhs.risk_mode         == rhs.risk_mode &&
           lhs.risk_percent      == rhs.risk_percent &&
           lhs.lots              == rhs.lots &&
           lhs.entry_price       == rhs.entry_price &&
           lhs.sl_price          == rhs.sl_price &&
           lhs.tp_price          == rhs.tp_price &&
           lhs.sl_points         == rhs.sl_points &&
           lhs.tp_points         == rhs.tp_points &&
           lhs.account_balance   == rhs.account_balance &&
           lhs.metadata_revision == rhs.metadata_revision);
  }

void BuildPreviewFinancialKey(const PreviewSnapshot &snapshot,
                              PreviewFinancialKey   &key)
  {
   key.Clear();
   if(!snapshot.visible)
      return;

   key.valid            = true;
   key.action           = snapshot.action;
   key.risk_mode        = g_state.risk_mode;
   key.risk_percent     = NormalizeDouble(g_state.risk_percent, 4);
   key.lots             = NormalizeDouble(g_state.lots, VolumeDigits());
   key.entry_price      = NormalizePriceValue(snapshot.entry_price);
   key.sl_price         = (snapshot.sl_price > 0.0) ? NormalizePriceValue(snapshot.sl_price) : 0.0;
   key.tp_price         = (snapshot.tp_price > 0.0) ? NormalizePriceValue(snapshot.tp_price) : 0.0;
   key.sl_points        = MathMax(0.0, MathRound(g_state.sl_points));
   key.tp_points        = MathMax(0.0, MathRound(g_state.tp_points));
   key.account_balance  = NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE), 2);
   key.metadata_revision = CurrentSymbolMetadataRevision();
  }

//+------------------------------------------------------------------+
//|  ██  4A.1: Preview snapshot + geometry renderer                  |
//+------------------------------------------------------------------+

bool BuildPreviewGeometrySnapshot(PreviewSnapshot &snapshot)
  {
   snapshot.Clear();

   if(g_state.action == ACTION_NONE || !InpShowPreview)
      return false;

   snapshot.action      = g_state.action;
   snapshot.is_buy      = IsBuyAction(g_state.action);
   snapshot.entry_price = EffectiveStateEntryPrice(g_state.action);
   if(snapshot.entry_price <= 0.0)
      return false;

   if(IsMarketAction(g_state.action))
      SyncMarketPointsFromAbsoluteTargets(snapshot.entry_price);

   snapshot.sl_price = EffectiveStateSLPrice(g_state.action, snapshot.entry_price);
   snapshot.tp_price = EffectiveStateTPPrice(g_state.action, snapshot.entry_price);

   snapshot.effective_label    = EffectiveActionLabel(g_state.action, snapshot.entry_price);
   snapshot.short_label        = ShortPreviewLabel(g_state.action, snapshot.entry_price);
   snapshot.entry_line_tooltip = snapshot.effective_label + " @ " + FormatPrice(snapshot.entry_price);
   snapshot.sl_line_tooltip    = (snapshot.sl_price > 0.0)
                                 ? "SL @ " + FormatPrice(snapshot.sl_price)
                                 : "";
   snapshot.tp_line_tooltip    = (snapshot.tp_price > 0.0)
                                 ? "TP @ " + FormatPrice(snapshot.tp_price)
                                 : "";

   snapshot.visible = true;
   return true;
  }

bool EnsurePreviewFinancialState(const PreviewSnapshot &snapshot)
  {
   PreviewFinancialKey next_key;
   BuildPreviewFinancialKey(snapshot, next_key);
   if(!next_key.valid)
     {
      InvalidatePreviewFinancialState();
      return false;
     }

   if(!g_preview_financial_dirty &&
      g_preview_financial_state.ready &&
      PreviewFinancialKeysMatch(g_preview_financial_key, next_key))
      return true;

   PreviewFinancialState next_state;
   next_state.Clear();
   next_state.plan_built = BuildTradePlan(next_state.plan, next_state.build_reason);
   next_state.plan_valid = next_state.plan_built &&
                           ValidateTradeRequest(next_state.plan, next_state.validation_message);
   if(!next_state.plan_built)
      next_state.validation_message = next_state.build_reason;
   next_state.ready = true;

   g_preview_financial_key   = next_key;
   g_preview_financial_state = next_state;
   g_preview_financial_dirty = false;
   g_perf_preview_financial_refresh_count++;
   TracePerfEvent("preview financial state refreshed");
   return true;
  }

void ApplyPreviewFinancialStateToSnapshot(PreviewSnapshot &snapshot)
  {
   snapshot.plan_valid = (g_preview_financial_state.ready &&
                          g_preview_financial_state.plan_valid);
   snapshot.plan_lots    = snapshot.plan_valid ? g_preview_financial_state.plan.lots : g_state.lots;
   snapshot.risk_money   = snapshot.plan_valid ? g_preview_financial_state.plan.risk_money : 0.0;
   snapshot.reward_money = snapshot.plan_valid ? g_preview_financial_state.plan.reward_money : 0.0;
   snapshot.risk_pct     = snapshot.plan_valid ? g_preview_financial_state.plan.risk_pct : 0.0;
   snapshot.reward_pct   = snapshot.plan_valid ? g_preview_financial_state.plan.reward_pct : 0.0;

   snapshot.en_label = snapshot.short_label + " " + FormatPrice(snapshot.entry_price) +
                       " | Lots " + FormatLots(snapshot.plan_lots);

   if(snapshot.sl_price > 0.0)
     {
      if(snapshot.plan_valid && snapshot.risk_money > 0.0)
        {
         snapshot.sl_label = StringFormat("SL %s | -$%.2f",
                                          FormatPrice(snapshot.sl_price),
                                          snapshot.risk_money);
         if(snapshot.risk_pct > 0.0)
            snapshot.sl_label += StringFormat(" | %.2f%%", snapshot.risk_pct);
        }
      else
         snapshot.sl_label = "SL " + FormatPrice(snapshot.sl_price);
     }

   if(snapshot.tp_price > 0.0)
     {
      if(snapshot.plan_valid && snapshot.reward_money > 0.0)
        {
         snapshot.tp_label = StringFormat("TP %s | +$%.2f",
                                          FormatPrice(snapshot.tp_price),
                                          snapshot.reward_money);
         if(snapshot.reward_pct > 0.0)
            snapshot.tp_label += StringFormat(" | %.2f%%", snapshot.reward_pct);
        }
      else
         snapshot.tp_label = "TP " + FormatPrice(snapshot.tp_price);
     }
  }

bool BuildPreviewSnapshot(PreviewSnapshot &snapshot)
  {
   if(!BuildPreviewGeometrySnapshot(snapshot))
      return false;

   EnsurePreviewFinancialState(snapshot);
   ApplyPreviewFinancialStateToSnapshot(snapshot);
   return true;
  }

void UpdatePreviewZonesFromSnapshot(const PreviewSnapshot &snapshot,
                                    const datetime        t1,
                                    const datetime        t2)
  {
   double entry_price = snapshot.entry_price;
   double sl_price    = snapshot.sl_price;
   double tp_price    = snapshot.tp_price;
   double band        = ENTRY_BAND_HALF_PTS * _Point;

   // ── zone_sep: align TP/SL inner edges with the entry band outer edges.
   double zone_sep = band;

   if(tp_price > 0.0)
     {
      double tp_hi, tp_lo;
      if(tp_price > entry_price)
        { tp_hi = tp_price; tp_lo = entry_price + zone_sep; }
      else
        { tp_hi = entry_price - zone_sep; tp_lo = tp_price; }

      DrawPreviewZone("tp", t1, t2, tp_hi, tp_lo,
                      CLR_PREV_TP_FILL, CLR_PREV_TP_BORDER,
                      CLR_PREV_TP_TEXT, snapshot.tp_label, tp_price);
     }
   else
     {
      ErasePreviewZone("tp");
     }

   if(sl_price > 0.0)
     {
      double sl_hi, sl_lo;
      if(sl_price < entry_price)
        { sl_hi = entry_price - zone_sep; sl_lo = sl_price; }
      else
        { sl_hi = sl_price; sl_lo = entry_price + zone_sep; }

      DrawPreviewZone("sl", t1, t2, sl_hi, sl_lo,
                      CLR_PREV_SL_FILL, CLR_PREV_SL_BORDER,
                      CLR_PREV_SL_TEXT, snapshot.sl_label, sl_price);
     }
   else
     {
      ErasePreviewZone("sl");
     }

   DrawPreviewZone("en", t1, t2,
                   entry_price + band, entry_price - band,
                   CLR_PREV_EN_FILL, CLR_PREV_EN_BORDER,
                   CLR_PREV_EN_TEXT, snapshot.en_label, entry_price);
   UpdateOverlayPreviewLabelsFromSnapshot(snapshot, t1, t2);
  }

void RenderPreviewFromSnapshot(const PreviewSnapshot &snapshot,
                               const bool             do_redraw)
  {
   if(!snapshot.visible)
     {
      DeletePreviewObjects();
      return;
     }

   datetime t1, t2;
   CalcPreviewTimeRange(t1, t2);
   RememberPreviewGeometryState(t2);
   g_perf_preview_geometry_refresh_count++;

   EnsurePreviewLine("entry", snapshot.entry_price,
                     CLR_ENTRY_LINE, STYLE_DOT, 1,
                     snapshot.entry_line_tooltip);
   if(snapshot.sl_price > 0.0)
      EnsurePreviewLine("sl", snapshot.sl_price, CLR_SL_LINE, STYLE_DOT, 1,
                        snapshot.sl_line_tooltip);
   else
     {
      string sl_ln = PREV_PFX + "sl_line";
      if(ObjectFind(0, sl_ln) >= 0) ObjectDelete(0, sl_ln);
      EraseOverlayLabel("sl");
     }
   if(snapshot.tp_price > 0.0)
      EnsurePreviewLine("tp", snapshot.tp_price, CLR_TP_LINE, STYLE_DOT, 1,
                        snapshot.tp_line_tooltip);
   else
     {
      string tp_ln = PREV_PFX + "tp_line";
      if(ObjectFind(0, tp_ln) >= 0) ObjectDelete(0, tp_ln);
      EraseOverlayLabel("tp");
     }

   UpdatePreviewZonesFromSnapshot(snapshot, t1, t2);

   if(do_redraw)
      RequestChartRedraw();
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

void UpdatePreviewGeometryOnly(const bool do_redraw)
  {
   if(g_state.action == ACTION_NONE || !InpShowPreview)
     {
      DeletePreviewObjects();
      return;
     }

   if(ShouldRefreshPreviewOnPulse())
     {
      UpdatePreview(do_redraw);
      return;
     }

   if(CanUseOverlayOnlyPreviewRefresh())
     {
      datetime t1, t2;
      CalcPreviewTimeRange(t1, t2);
      UpdateOverlayPreviewLabelsFromSnapshot(g_preview_snapshot, t1, t2);
      g_perf_preview_overlay_only_refresh_count++;
      if(do_redraw)
         RequestChartRedraw();
      return;
     }

   RenderPreviewFromSnapshot(g_preview_snapshot, do_redraw);
  }

void UpdatePreview(const bool do_redraw)
  {
   PreviewSnapshot snapshot;
   if(!BuildPreviewSnapshot(snapshot))
     {
      DeletePreviewObjects();
      return;
     }

   g_preview_snapshot       = snapshot;
   g_preview_snapshot_ready = true;
   g_preview_dirty          = false;
   g_preview_market_entry_key = IsMarketAction(snapshot.action)
                                ? NormalizePriceValue(snapshot.entry_price)
                                : 0.0;

   RenderPreviewFromSnapshot(snapshot, do_redraw);

   if(!g_status_sticky && IsPendingAction(g_state.action))
      SetStatus("Ação: " + snapshot.effective_label + ". Configure e clique Send.");
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
   if(IsMouseNearPanel(mx, my)) return "";

   double entry_p = EffectiveStateEntryPrice(g_state.action);
   double sl_p    = EffectiveStateSLPrice(g_state.action, entry_p);
   double tp_p    = EffectiveStateTPPrice(g_state.action, entry_p);

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
          if(mx>=_bx-OVL_HIT_PAD_PX && mx<=_bx+_bw+OVL_HIT_PAD_PX &&
             my>=_by-OVL_HIT_PAD_PX && my<=_by+_bh+OVL_HIT_PAD_PX) return "entry";
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
          if(mx>=_bx-OVL_HIT_PAD_PX && mx<=_bx+_bw+OVL_HIT_PAD_PX &&
             my>=_by-OVL_HIT_PAD_PX && my<=_by+_bh+OVL_HIT_PAD_PX) return "sl";
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
          if(mx>=_bx-OVL_HIT_PAD_PX && mx<=_bx+_bw+OVL_HIT_PAD_PX &&
             my>=_by-OVL_HIT_PAD_PX && my<=_by+_bh+OVL_HIT_PAD_PX) return "tp";
         }
      }
   }

   return "";
  }

bool ResolveDragPriceFromMouse(const int mx, const int my, double &out_price)
  {
   int      subwin;
   datetime t_dummy;
   double   price = 0.0;

   if(ChartXYToTimePrice(0, mx, my, subwin, t_dummy, price) && price > 0.0)
     {
      out_price = price;
      return true;
     }

   int chart_w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chart_h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(chart_w <= 1 || chart_h <= 1)
      return false;

   int clamped_x = MathMax(0, MathMin(chart_w - 2, mx));
   int clamped_y = MathMax(0, MathMin(chart_h - 2, my));

   if(ChartXYToTimePrice(0, clamped_x, clamped_y, subwin, t_dummy, price) && price > 0.0)
     {
      out_price = price;
      return true;
     }

   for(int dx = 1; dx <= LINE_HIT_TOL_PX; dx++)
     {
      int probe_x = MathMax(0, clamped_x - dx);
      if(ChartXYToTimePrice(0, probe_x, clamped_y, subwin, t_dummy, price) && price > 0.0)
        {
         out_price = price;
         return true;
        }
     }

   return false;
  }

bool ApplyLineDrag(const int mx, const int my)
  {
   bool is_buy    = IsBuyAction(g_state.action);
   bool is_market = IsMarketAction(g_state.action);
   double old_entry_price     = g_state.entry_price;
   double old_sl_points       = g_state.sl_points;
   double old_tp_points       = g_state.tp_points;
   double old_market_sl_price = g_state.market_sl_price;
   double old_market_tp_price = g_state.market_tp_price;
   double   new_price;
   if(!ResolveDragPriceFromMouse(mx, my, new_price)) return false;
   if(new_price <= 0.0) return false;

   double tick_sz = SymbolTickSizeCached();
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
         if(is_market)
            g_state.market_sl_price = new_price;
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
         if(is_market)
            g_state.market_tp_price = new_price;
        }
     }
   return (g_state.entry_price      != old_entry_price     ||
           g_state.sl_points        != old_sl_points       ||
           g_state.tp_points        != old_tp_points       ||
           g_state.market_sl_price  != old_market_sl_price ||
           g_state.market_tp_price  != old_market_tp_price);
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

   double tick_sz = SymbolTickSizeCached();
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
         if(is_market)
            g_state.market_sl_price = new_price;
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
         if(is_market)
            g_state.market_tp_price = new_price;
        }
     }
   else
     {
      return;   // not one of our lines
     }

   // Deselect the line so it doesn't stay highlighted with anchor points
   ObjectSetInteger(0, obj_name, OBJPROP_SELECTED, false);
   g_native_preview_line_dragging = false;
   g_native_preview_line_kind     = "";

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

   RefreshNativePreviewLineDragState(btn_down);
   UpdatePanelScrollCapture(mx, my);

   if(HandlePanelEdgeGrabDrag(mx, my, btn_down))
     {
      UpdatePanelScrollCapture(mx, my);
      return;
     }

   // ── Release: clean up any active overlay drag ────────────────────
   if(!btn_down)
     {
      if(g_drag_phase == DRAG_ACTIVE_LINE)
        {
         g_drag_phase     = DRAG_IDLE;
         g_drag_line_kind = "";
        }
      else if(g_drag_phase == DRAG_CANDIDATE)
        {
         g_drag_phase     = DRAG_IDLE;
         g_drag_line_kind = "";
        }
      UpdatePanelScrollCapture(mx, my);
      return;
     }

   // ── CRITICAL GUARD: if mouse is over the panel, never start a drag ──
   if(g_drag_phase == DRAG_IDLE && IsMouseNearPanel(mx, my))
      return;

   if(g_native_preview_line_dragging)
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
      if(ApplyLineDrag(mx, my))
        {
         g_panel.RefreshValues();
         UpdatePreview();
        }
      return;
     }
  }
