//+------------------------------------------------------------------+
//|  ██  CLotForgePanel :: EVENT MAP                                  |
//|                                                                  |
//|  Uses standard CAppDialog EVENT_MAP macros.                      |
//|  ON_EVENT(event_type, control_member, handler_method)            |
//|  CAppDialog transforms raw CHARTEVENT_* into internal ON_CLICK,  |
//|  ON_END_EDIT etc. IDs before dispatching to OnEvent().           |
//+------------------------------------------------------------------+

EVENT_MAP_BEGIN(CLotForgePanel)
ON_EVENT(ON_CLICK, m_BtnRiskMode,     OnClickRiskMode)
ON_EVENT(ON_CLICK, m_BtnPrimaryUp,    OnClickPrimaryUp)
ON_EVENT(ON_CLICK, m_BtnPrimaryDn,    OnClickPrimaryDn)
ON_EVENT(ON_CLICK, m_BtnEntryUp,      OnClickEntryUp)
ON_EVENT(ON_CLICK, m_BtnEntryDn,      OnClickEntryDn)
ON_EVENT(ON_CLICK, m_BtnTPUp,         OnClickTPUp)
ON_EVENT(ON_CLICK, m_BtnTPDn,         OnClickTPDn)
ON_EVENT(ON_CLICK, m_BtnSLUp,         OnClickSLUp)
ON_EVENT(ON_CLICK, m_BtnSLDn,         OnClickSLDn)
ON_EVENT(ON_CLICK, m_BtnSell,         OnClickSell)
ON_EVENT(ON_CLICK, m_BtnBuy,          OnClickBuy)
ON_EVENT(ON_CLICK, m_BtnSellPending,  OnClickSellPending)
ON_EVENT(ON_CLICK, m_BtnBuyPending,   OnClickBuyPending)
ON_EVENT(ON_CLICK, m_BtnBE,           OnClickBE)
ON_EVENT(ON_CLICK, m_ChkAutoBE,       OnClickAutoBE)
ON_EVENT(ON_CLICK, m_ChkAutoTrailing, OnClickAutoTrailing)
ON_EVENT(ON_CLICK, m_BtnAlgoTrading,  OnClickAlgoTrading)
ON_EVENT(ON_CLICK, m_BtnCancel,       OnClickCancel)
ON_EVENT(ON_CLICK, m_BtnSend,         OnClickSend)
ON_EVENT(ON_END_EDIT, m_EdtPrimary,   OnEndEditPrimary)
ON_EVENT(ON_END_EDIT, m_EdtEntry,     OnEndEditEntry)
ON_EVENT(ON_END_EDIT, m_EdtTP,        OnEndEditTP)
ON_EVENT(ON_END_EDIT, m_EdtSL,        OnEndEditSL)
EVENT_MAP_END(CAppDialog)

//+------------------------------------------------------------------+
//|  CLotForgePanel :: CreateInlineGroup                              |
//|  Creates: [Label LABEL_W][Edit EDIT_W][▲ SPIN_W][▼ SPIN_W]      |
//+------------------------------------------------------------------+

bool CLotForgePanel::CreateInlineGroup(const int x, const int y,
                                        CButton &lbl, const string lbl_text,
                                        CEdit &edt, const string edt_text,
                                        CButton &btn_up, CButton &btn_dn,
                                        const int lbl_w, const int edt_w)
  {
   if(!lbl.Create(m_chart_id, m_name + "_lbl_" + lbl_text, m_subwin,
      x, y, x + lbl_w, y + ROW_H)) return false;
   lbl.Text(lbl_text);
   lbl.Color(C'110,110,110');
   lbl.ColorBackground(clrWhite);
   if(!Add(lbl)) return false;

   int ex = x + lbl_w;
   if(!edt.Create(m_chart_id, m_name + "_edt_" + lbl_text, m_subwin,
      ex, y, ex + edt_w, y + EDIT_H)) return false;
   edt.Text(edt_text);
   if(!Add(edt)) return false;

   int sx = ex + edt_w + 1;
   if(!btn_up.Create(m_chart_id, m_name + "_up_" + lbl_text, m_subwin,
      sx, y, sx + SPIN_W, y + SPIN_H)) return false;
   btn_up.Text("+");
   btn_up.FontSize(7);
   if(!Add(btn_up)) return false;

   if(!btn_dn.Create(m_chart_id, m_name + "_dn_" + lbl_text, m_subwin,
      sx, y + SPIN_H + 1, sx + SPIN_W, y + ROW_H)) return false;
   btn_dn.Text("-");
   btn_dn.FontSize(7);
   if(!Add(btn_dn)) return false;

   return true;
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: CreateRiskModeGroup                            |
//|  Creates: [RiskMode btn][Edit][▲][▼]                             |
//+------------------------------------------------------------------+

bool CLotForgePanel::CreateRiskModeGroup(const int x, const int y,
                                          const int lbl_w, const int edt_w)
  {
   string mode_text = (g_state.risk_mode == RISK_MODE_PERCENT) ? "Risk%"
                      : (g_state.risk_mode == RISK_MODE_MONEY) ? "Money"
                      : "Lots";

   if(!m_BtnRiskMode.Create(m_chart_id, m_name + "_btn_riskmode", m_subwin,
      x, y, x + lbl_w, y + ROW_H)) return false;
   m_BtnRiskMode.Text(mode_text);
   m_BtnRiskMode.ColorBackground(clrWhite);
   m_BtnRiskMode.Color(clrBlack);
   if(!Add(m_BtnRiskMode)) return false;

   int ex = x + lbl_w;
   string val_text = (g_state.risk_mode == RISK_MODE_PERCENT)
                     ? FormatPercent(g_state.risk_percent)
                     : (g_state.risk_mode == RISK_MODE_MONEY)
                       ? FormatMoney(g_state.risk_money)
                       : FormatLots(g_state.lots);
   if(!m_EdtPrimary.Create(m_chart_id, m_name + "_edt_primary", m_subwin,
      ex, y, ex + edt_w, y + EDIT_H)) return false;
   m_EdtPrimary.Text(val_text);
   if(!Add(m_EdtPrimary)) return false;

   int sx = ex + edt_w + 2;
   if(!m_BtnPrimaryUp.Create(m_chart_id, m_name + "_up_primary", m_subwin,
      sx, y, sx + SPIN_W, y + SPIN_H)) return false;
   m_BtnPrimaryUp.Text("+");
   m_BtnPrimaryUp.FontSize(7);
   if(!Add(m_BtnPrimaryUp)) return false;

   if(!m_BtnPrimaryDn.Create(m_chart_id, m_name + "_dn_primary", m_subwin,
      sx, y + SPIN_H + 1, sx + SPIN_W, y + ROW_H)) return false;
   m_BtnPrimaryDn.Text("-");
   m_BtnPrimaryDn.FontSize(7);
   if(!Add(m_BtnPrimaryDn)) return false;

   return true;
  }

void CLotForgePanel::SyncEditableFieldsToState(const bool include_primary)
  {
   double val = 0.0;
   bool tp_changed = false;
   bool sl_changed = false;

   if(include_primary && ParseDoubleText(m_EdtPrimary.Text(), val))
     {
      if(g_state.risk_mode == RISK_MODE_PERCENT)
         g_state.risk_percent = MathMax(0.0, val);
      else if(g_state.risk_mode == RISK_MODE_MONEY)
         g_state.risk_money = MathMax(0.0, NormalizeDouble(val, 2));
      else
         g_state.lots = NormalizeVolumeValue(val);
     }

   if(ParseDoubleText(m_EdtEntry.Text(), val))
      g_state.entry_price = (val <= 0.0) ? 0.0 : NormalizePriceValue(val);

   if(ParseDoubleText(m_EdtTP.Text(), val))
     {
      double next_tp = MathMax(0.0, MathRound(val));
      tp_changed = (next_tp != g_state.tp_points);
      g_state.tp_points = next_tp;
     }

   if(ParseDoubleText(m_EdtSL.Text(), val))
     {
      double next_sl = MathMax(0.0, MathRound(val));
      sl_changed = (next_sl != g_state.sl_points);
      g_state.sl_points = next_sl;
     }

   if(tp_changed || sl_changed)
      ClearMarketPriceTargets();
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: CreatePanel                                    |
//|                                                                  |
//|  v2.0 layout (no comment, no trailing/auto rows):                |
//|  Row 1: [Lots/Risk% 90][val 70][±17]  [Entry][val][±]           |
//|  Row 2: [TP][val][±]          [SL][val][±]                       |
//|  Row 3: [Sell 145]  [BE ~46]  [Buy 145]                         |
//|  Row 4: [Sell Pending]        [Buy Pending]                      |
//|  Row 5: [☐ Algo Trading]                      (full width)       |
//|  Row 6: [Cancel]              [Send]                             |
//+------------------------------------------------------------------+

bool CLotForgePanel::CreatePanel(const long chart, const string name,
                                  const int subwin, const int x1, const int y1)
  {
   int x2 = x1 + PANEL_W;
   int y2 = y1 + PANEL_H;
   if(!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2))
      return false;

   m_content_w = ClientAreaWidth() - 6;
   m_col_w     = (m_content_w - COL_GAP) / 2;

   int cx = 3;
   int cy = 2;

   // ── Row 1: RiskMode group (left) + Entry group (right) ─────────
   //  v2.1: symmetric columns — same split as TP/SL row
   int sym_col_w = (m_content_w - COL_GAP) / 2;
   int sym_edt_w = sym_col_w - INLINE_LABEL_W - SPIN_W - 1;

   if(!CreateRiskModeGroup(cx, cy, INLINE_LABEL_W, sym_edt_w)) return false;
   int rx = cx + sym_col_w + COL_GAP;
   if(!CreateInlineGroup(rx, cy,
         m_LblEntry, "Entry",
         m_EdtEntry, g_state.entry_price <= 0.0 ? "0" : FormatPrice(g_state.entry_price),
         m_BtnEntryUp, m_BtnEntryDn,
         INLINE_LABEL_W, sym_edt_w)) return false;
   cy += ROW_H + ROW_GAP;

   // ── Row 2: TP group + SL group (same symmetric columns) ────────
   if(!CreateInlineGroup(cx, cy,
         m_LblTP, "TP",
         m_EdtTP, FormatPoints(g_state.tp_points),
         m_BtnTPUp, m_BtnTPDn,
         INLINE_LABEL_W, sym_edt_w)) return false;
   int rx2 = cx + sym_col_w + COL_GAP;
   if(!CreateInlineGroup(rx2, cy,
         m_LblSL, "SL",
         m_EdtSL, FormatPoints(g_state.sl_points),
         m_BtnSLUp, m_BtnSLDn,
         INLINE_LABEL_W, sym_edt_w)) return false;
   cy += ROW_H + SECTION_GAP;

   // ── Row 3: Sell | BE | Buy (3-column) ──────────────────────────
   int sell_buy_w = 145;
   int be_gap     = 2;
   int be_w       = m_content_w - sell_buy_w * 2 - be_gap * 2;

   if(!m_BtnSell.Create(chart, name + "_btn_sell", subwin,
      cx, cy, cx + sell_buy_w, cy + ACTION_BTN_H)) return false;
   m_BtnSell.Text("Sell");
   m_BtnSell.ColorBackground(CLR_SELL_BG);
   m_BtnSell.Color(clrWhite);
   m_BtnSell.ColorBorder(clrWhite);
   if(!Add(m_BtnSell)) return false;

   int be_x = cx + sell_buy_w + be_gap;
   if(!m_BtnBE.Create(chart, name + "_btn_be", subwin,
      be_x, cy, be_x + be_w, cy + ACTION_BTN_H)) return false;
   m_BtnBE.Text("BE");
   m_BtnBE.ColorBackground(CLR_BE_BG);
   m_BtnBE.Color(clrWhite);
   m_BtnBE.ColorBorder(clrWhite);
   if(!Add(m_BtnBE)) return false;

   int buy_x = be_x + be_w + be_gap;
   if(!m_BtnBuy.Create(chart, name + "_btn_buy", subwin,
      buy_x, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnBuy.Text("Buy");
   m_BtnBuy.ColorBackground(CLR_BUY_BG);
   m_BtnBuy.Color(clrWhite);
   m_BtnBuy.ColorBorder(clrWhite);
   if(!Add(m_BtnBuy)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row 4: Sell Pending | Buy Pending ──────────────────────────
   int btn_w = (m_content_w - 4) / 2;

   if(!m_BtnSellPending.Create(chart, name + "_btn_sellp", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnSellPending.Text("Sell Pending");
   m_BtnSellPending.ColorBackground(CLR_SELL_BG);
   m_BtnSellPending.Color(clrWhite);
   m_BtnSellPending.ColorBorder(clrWhite);
   if(!Add(m_BtnSellPending)) return false;

   if(!m_BtnBuyPending.Create(chart, name + "_btn_buyp", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnBuyPending.Text("Buy Pending");
   m_BtnBuyPending.ColorBackground(CLR_BUY_BG);
   m_BtnBuyPending.Color(clrWhite);
   m_BtnBuyPending.ColorBorder(clrWhite);
   if(!Add(m_BtnBuyPending)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row 5: Auto BE | Auto Trailing (same style as Cancel/Send) ──
   {
    string chk_be_text    = g_state.break_even_enabled    ? "[X] Auto BE"      : "[ ] Auto BE";
    string chk_trail_text = g_state.trailing_stop_enabled ? "[X] Auto Trailing" : "[ ] Auto Trailing";

    if(!m_ChkAutoBE.Create(chart, name + "_chk_autobe", subwin,
       cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
    m_ChkAutoBE.Text(chk_be_text);
    m_ChkAutoBE.ColorBackground(g_state.break_even_enabled ? CLR_CHK_ON_BG : CLR_NEUTRAL_BG);
    m_ChkAutoBE.Color(g_state.break_even_enabled ? clrWhite : clrBlack);
    m_ChkAutoBE.ColorBorder(CLR_NEUTRAL_BORDER);
    if(!Add(m_ChkAutoBE)) return false;

    if(!m_ChkAutoTrailing.Create(chart, name + "_chk_autotrail", subwin,
       cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
    m_ChkAutoTrailing.Text(chk_trail_text);
    m_ChkAutoTrailing.ColorBackground(g_state.trailing_stop_enabled ? CLR_CHK_ON_BG : CLR_NEUTRAL_BG);
    m_ChkAutoTrailing.Color(g_state.trailing_stop_enabled ? clrWhite : clrBlack);
    m_ChkAutoTrailing.ColorBorder(CLR_NEUTRAL_BORDER);
    if(!Add(m_ChkAutoTrailing)) return false;
   }
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row 6: Algo Trading (same style as Cancel/Send, checkbox) ──
   {
    string algo_text = g_state.algo_trading_ui_enabled ? "[X] Algo Trading" : "[ ] Algo Trading";
    if(!m_BtnAlgoTrading.Create(chart, name + "_btn_algo", subwin,
       cx, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
    m_BtnAlgoTrading.Text(algo_text);
    m_BtnAlgoTrading.ColorBackground(g_state.algo_trading_ui_enabled ? CLR_CHK_ON_BG : CLR_NEUTRAL_BG);
    m_BtnAlgoTrading.Color(g_state.algo_trading_ui_enabled ? clrWhite : clrBlack);
    m_BtnAlgoTrading.ColorBorder(CLR_NEUTRAL_BORDER);
    if(!Add(m_BtnAlgoTrading)) return false;
   }
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row 7: Cancel | Send ───────────────────────────────────────
   if(!m_BtnCancel.Create(chart, name + "_btn_cancel", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnCancel.Text("Cancel");
   m_BtnCancel.ColorBackground(CLR_NEUTRAL_BG);
   m_BtnCancel.Color(clrBlack);
   m_BtnCancel.ColorBorder(CLR_NEUTRAL_BORDER);
   if(!Add(m_BtnCancel)) return false;

   if(!m_BtnSend.Create(chart, name + "_btn_send", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnSend.Text("Send");
   m_BtnSend.ColorBackground(CLR_NEUTRAL_BG);
   m_BtnSend.Color(clrBlack);
   m_BtnSend.ColorBorder(CLR_NEUTRAL_BORDER);
   if(!Add(m_BtnSend)) return false;

   // ── Apply two-blue chrome AFTER all controls are added ─────────
   {
    string dlg_n  = Name();
    int    n_objs = ObjectsTotal(chart, subwin, -1);
    for(int k = 0; k < n_objs; k++)
      {
       string      obj_n = ObjectName(chart, k, subwin, -1);
       if(StringFind(obj_n, dlg_n) != 0) continue;
       string      sfx   = StringSubstr(obj_n, StringLen(dlg_n));
       ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(chart, obj_n, OBJPROP_TYPE);

       if(otype == OBJ_RECTANGLE_LABEL)
         {
          if(sfx == "ClientBack")
            {
             ObjectSetInteger(chart, obj_n, OBJPROP_BGCOLOR, CLR_PANEL_BG);
             ObjectSetInteger(chart, obj_n, OBJPROP_COLOR,   CLR_PANEL_BG);
            }
          else
            {
             ObjectSetInteger(chart, obj_n, OBJPROP_BGCOLOR, CLR_TITLE_BG);
             ObjectSetInteger(chart, obj_n, OBJPROP_COLOR,   CLR_TITLE_BG);
            }
         }
       else if(otype == OBJ_EDIT)
         {
          if(sfx == "Caption")
            {
             ObjectSetInteger(chart, obj_n, OBJPROP_BGCOLOR,      CLR_TITLE_BG);
             ObjectSetInteger(chart, obj_n, OBJPROP_BORDER_COLOR, CLR_TITLE_BG);
             ObjectSetInteger(chart, obj_n, OBJPROP_COLOR,        clrWhite);
            }
         }
       else if(otype == OBJ_BUTTON)
         {
          if(sfx == "Min" || sfx == "Close" || sfx == "Back")
            {
             ObjectSetInteger(chart, obj_n, OBJPROP_BGCOLOR, CLR_TITLE_BTN);
             ObjectSetInteger(chart, obj_n, OBJPROP_COLOR,   clrBlack);
            }
         }
      }
   }

   return true;
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: RefreshValues                                  |
//+------------------------------------------------------------------+

void CLotForgePanel::RefreshValues(void)
  {
   string mode_text = (g_state.risk_mode == RISK_MODE_PERCENT) ? "Risk%"
                      : (g_state.risk_mode == RISK_MODE_MONEY) ? "Money"
                      : "Lots";
   if(m_BtnRiskMode.Text() != mode_text) m_BtnRiskMode.Text(mode_text);

   string prim_text = (g_state.risk_mode == RISK_MODE_PERCENT)
                      ? FormatPercent(g_state.risk_percent)
                      : (g_state.risk_mode == RISK_MODE_MONEY)
                        ? FormatMoney(g_state.risk_money)
                        : FormatLots(g_state.lots);
   if(m_EdtPrimary.Text() != prim_text) m_EdtPrimary.Text(prim_text);

   string entry_text = g_state.entry_price <= 0.0 ? "0" : FormatPrice(g_state.entry_price);
   if(m_EdtEntry.Text() != entry_text) m_EdtEntry.Text(entry_text);

   string tp_text = FormatPoints(g_state.tp_points);
   if(m_EdtTP.Text() != tp_text) m_EdtTP.Text(tp_text);

   string sl_text = FormatPoints(g_state.sl_points);
   if(m_EdtSL.Text() != sl_text) m_EdtSL.Text(sl_text);

  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: ApplyActionStyle / RefreshActionButtons        |
//+------------------------------------------------------------------+

void CLotForgePanel::ApplyActionStyle(CButton &btn, const color base_clr, const bool selected)
  {
   btn.ColorBackground(base_clr);
   btn.ColorBorder(selected ? CLR_SELECTED_BORDER : clrWhite);
  }

void CLotForgePanel::RefreshActionButtons(void)
  {
   ApplyActionStyle(m_BtnSell,        CLR_SELL_BG, g_state.action == ACTION_SELL);
   ApplyActionStyle(m_BtnBuy,         CLR_BUY_BG,  g_state.action == ACTION_BUY);
   ApplyActionStyle(m_BtnSellPending, CLR_SELL_BG, g_state.action == ACTION_SELL_PENDING);
   ApplyActionStyle(m_BtnBuyPending,  CLR_BUY_BG,  g_state.action == ACTION_BUY_PENDING);

   // Cancel/Send: neutral border, not white
   color cs = (g_state.action != ACTION_NONE) ? C'180,190,208' : CLR_NEUTRAL_BG;
   m_BtnCancel.ColorBackground(cs);
   m_BtnCancel.ColorBorder(CLR_NEUTRAL_BORDER);
   m_BtnSend.ColorBackground(cs);
   m_BtnSend.ColorBorder(CLR_NEUTRAL_BORDER);

   RefreshBETrailingButtons();
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: RefreshBETrailingButtons                       |
//|  Updates Auto BE / Auto Trailing checkbox appearance to reflect   |
//|  current g_state.break_even_enabled / trailing_stop_enabled.     |
//+------------------------------------------------------------------+

void CLotForgePanel::RefreshBETrailingButtons(void)
  {
   // Auto BE checkbox
   bool be_on = g_state.break_even_enabled;
   m_ChkAutoBE.Text(be_on ? "[X] Auto BE" : "[ ] Auto BE");
   m_ChkAutoBE.ColorBackground(be_on ? CLR_CHK_ON_BG : CLR_NEUTRAL_BG);
   m_ChkAutoBE.Color(be_on ? clrWhite : clrBlack);

   // Auto Trailing checkbox
   bool trail_on = g_state.trailing_stop_enabled;
   m_ChkAutoTrailing.Text(trail_on ? "[X] Auto Trailing" : "[ ] Auto Trailing");
   m_ChkAutoTrailing.ColorBackground(trail_on ? CLR_CHK_ON_BG : CLR_NEUTRAL_BG);
   m_ChkAutoTrailing.Color(trail_on ? clrWhite : clrBlack);

   // Algo Trading checkbox
   bool algo_on = g_state.algo_trading_ui_enabled;
   m_BtnAlgoTrading.Text(algo_on ? "[X] Algo Trading" : "[ ] Algo Trading");
   m_BtnAlgoTrading.ColorBackground(algo_on ? CLR_CHK_ON_BG : CLR_NEUTRAL_BG);
   m_BtnAlgoTrading.Color(algo_on ? clrWhite : clrBlack);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: IsMouseOverPanel                               |
//+------------------------------------------------------------------+

bool CLotForgePanel::IsMouseOverPanel(const int mx, const int my)
  {
   int x1 = (int)Left();
   int y1 = (int)Top();
   int x2 = (int)Right();
   int y2 = (int)Bottom();
   return (mx >= x1 && mx <= x2 && my >= y1 && my <= y2);
  }

bool CLotForgePanel::IsMouseNearPanel(const int mx, const int my)
  {
   int x1 = (int)Left()   - PANEL_PROXIMITY_PX;
   int y1 = (int)Top()    - PANEL_PROXIMITY_PX;
   int x2 = (int)Right()  + PANEL_PROXIMITY_PX;
   int y2 = (int)Bottom() + PANEL_PROXIMITY_PX;
   return (mx >= x1 && mx <= x2 && my >= y1 && my <= y2);
  }

void CLotForgePanel::BeginActiveEdit(const CompactEditTarget target)
  {
   g_state.edit_in_progress = (target != EDIT_TARGET_NONE);
   g_state.editing_object   = target;
   g_state.active_edit      = target;
   SyncUiInteractionState();
  }

void CLotForgePanel::EndActiveEdit(void)
  {
   g_state.edit_in_progress = false;
   g_state.editing_object   = EDIT_TARGET_NONE;
   g_state.active_edit      = EDIT_TARGET_NONE;
   SyncUiInteractionState();
  }

bool CLotForgePanel::OwnsObject(const string obj_name)
  {
   string prefix = Name();
   return (prefix != "" && StringFind(obj_name, prefix) == 0);
  }

CompactEditTarget CLotForgePanel::ResolveEditTarget(const string obj_name)
  {
   string prefix = Name();
   if(prefix == "")
      return EDIT_TARGET_NONE;

   if(obj_name == prefix + "_edt_primary")
     {
      if(g_state.risk_mode == RISK_MODE_PERCENT)
         return EDIT_TARGET_RISK_PCT;
      if(g_state.risk_mode == RISK_MODE_MONEY)
         return EDIT_TARGET_RISK_MONEY;
      return EDIT_TARGET_LOTS;
     }
   if(obj_name == prefix + "_edt_entry")
      return EDIT_TARGET_ENTRY;
   if(obj_name == prefix + "_edt_tp")
      return EDIT_TARGET_TP;
   if(obj_name == prefix + "_edt_sl")
      return EDIT_TARGET_SL;

   return EDIT_TARGET_NONE;
  }

void SyncUiInteractionState()
  {
   g_ui_interaction_active = (g_panel_dragging ||
                              g_panel_manual_dragging ||
                              g_state.edit_in_progress);
  }

bool ShouldPauseUiHeavyRefresh()
  {
   return (g_ui_interaction_active ||
           g_drag_phase != DRAG_IDLE ||
           g_native_preview_line_dragging);
  }

void TrackUiInteractionEvent(const int id,
                             const long &lparam,
                             const double &dparam,
                             const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      CompactEditTarget target = g_panel.ResolveEditTarget(sparam);
      if(target != EDIT_TARGET_NONE)
        {
         g_panel.BeginActiveEdit(target);
         return;
        }

      if(g_state.edit_in_progress)
         g_panel.EndActiveEdit();
      return;
     }

   if(id == CHARTEVENT_CLICK)
     {
      if(g_state.edit_in_progress && !g_panel.IsMouseOverPanel((int)lparam, (int)dparam))
         g_panel.EndActiveEdit();
      return;
     }

   if(id == CHARTEVENT_OBJECT_DRAG && g_state.edit_in_progress)
      g_panel.EndActiveEdit();
  }

void CLotForgePanel::RememberPanelState(void)
  {
   if(m_minimized)
      m_min_rect.SetBound(m_rect);
   else
      m_norm_rect.SetBound(m_rect);

   g_state.panel_x   = (int)Left();
   g_state.panel_y   = (int)Top();
   g_state.minimized = m_minimized;
  }

void CLotForgePanel::BringPanelToFront(void)
  {
   int  saved_x = (int)Left();
   int  saved_y = (int)Top();
   bool was_min = m_minimized;

   if(was_min)
      m_min_rect.Move(saved_x, saved_y);
   else
      m_norm_rect.Move(saved_x, saved_y);

   Hide();
   Show();

   if(was_min)
      CAppDialog::Minimize();
   else
      CAppDialog::Maximize();

   RememberPanelState();
  }

bool CLotForgePanel::OnDialogDragStart(void)
  {
   bool handled = CAppDialog::OnDialogDragStart();
   g_panel_dragging = handled;
   SyncUiInteractionState();
   return handled;
  }

bool CLotForgePanel::OnDialogDragEnd(void)
  {
   bool handled = CAppDialog::OnDialogDragEnd();
   g_panel_dragging = false;
   SyncUiInteractionState();
   RememberPanelState();
   if(g_state.action != ACTION_NONE)
      UpdatePreviewGeometryOnly();
   if(!RefreshManagedTradeMarkersGeometryOnly())
      RefreshAllManagedTradeMarkers();
   return handled;
  }

void CLotForgePanel::OnClickCaption(void)
  {
   BringPanelToFront();
  }

void CLotForgePanel::OnClickButtonMinMax(void)
  {
   CAppDialog::OnClickButtonMinMax();
   BringPanelToFront();
  }

void CLotForgePanel::Minimize(void)
  {
   if(!m_minimized)
     {
      g_state.panel_x = (int)Left();
      g_state.panel_y = (int)Top();
      m_norm_rect.SetBound(m_rect);
     }

   m_min_rect.Move(g_state.panel_x, g_state.panel_y);
   CAppDialog::Minimize();
   RememberPanelState();
  }

void CLotForgePanel::Maximize(void)
  {
   if(m_minimized)
      m_min_rect.SetBound(m_rect);

   m_norm_rect.Move(g_state.panel_x, g_state.panel_y);
   CAppDialog::Maximize();
   RememberPanelState();
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: Event Handlers                                |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickRiskMode(void)
  {
   SyncEditableFieldsToState();

   string sync_reason = "";
   RiskMode next_mode = g_state.risk_mode;

   if(g_state.risk_mode == RISK_MODE_LOTS)
     {
      double next_risk_pct = 0.0;
      double entry_price   = EffectiveStateEntryPrice(g_state.action);
      double sl_price      = EffectiveStateSLPrice(g_state.action, entry_price);

      if(CalcRiskPercentFromLots(entry_price, sl_price, g_state.lots,
                                 IsBuyAction(g_state.action),
                                 next_risk_pct, sync_reason))
         g_state.risk_percent = next_risk_pct;
      else
        {
         g_state.risk_percent = 0.0;
         if(sync_reason != "")
            Print("[RISK MODE] Falha ao sincronizar Lots -> %: ", sync_reason);
         SetStatus("Modo Risk%: sem conversao valida; ajuste o percentual manualmente.");
        }
      next_mode = RISK_MODE_PERCENT;
     }
   else if(g_state.risk_mode == RISK_MODE_PERCENT)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance > 0.0 && g_state.risk_percent > 0.0)
         g_state.risk_money = NormalizeDouble(balance * g_state.risk_percent / 100.0, 2);
      else
        {
         g_state.risk_money = 0.0;
         SetStatus("Modo Money: sem conversao valida; ajuste o valor manualmente.");
        }
      next_mode = RISK_MODE_MONEY;
     }
   else
     {
      double next_lots   = 0.0;
      double entry_price = EffectiveStateEntryPrice(g_state.action);
      double sl_price    = EffectiveStateSLPrice(g_state.action, entry_price);

      if(CalcLotsFromRiskMoney(entry_price, sl_price, g_state.risk_money,
                               IsBuyAction(g_state.action),
                               next_lots, sync_reason))
         g_state.lots = next_lots;
      else
        {
         g_state.lots = 0.0;
         if(sync_reason != "")
            Print("[RISK MODE] Falha ao sincronizar Money -> Lots: ", sync_reason);
         SetStatus("Modo Lots: sem conversao valida; ajuste os lotes manualmente.");
        }
      next_mode = RISK_MODE_LOTS;
     }

   g_state.risk_mode = next_mode;
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickPrimaryUp(void)
  {
   if(g_state.risk_mode == RISK_MODE_PERCENT)
     { g_state.risk_percent = NormalizeDouble(g_state.risk_percent + 0.25, 2); }
   else if(g_state.risk_mode == RISK_MODE_MONEY)
     {
      double step = (g_state.risk_money < 10.0)  ? 0.50
                  : (g_state.risk_money < 100.0) ? 1.00
                  : (g_state.risk_money < 1000.0)? 5.00
                  : 10.00;
      g_state.risk_money = NormalizeDouble(g_state.risk_money + step, 2);
     }
   else
     { AdjustLots(+1); }
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickPrimaryDn(void)
  {
   if(g_state.risk_mode == RISK_MODE_PERCENT)
     { g_state.risk_percent = MathMax(0.0, NormalizeDouble(g_state.risk_percent - 0.25, 2)); }
   else if(g_state.risk_mode == RISK_MODE_MONEY)
     {
      double step = (g_state.risk_money <= 10.0)  ? 0.50
                  : (g_state.risk_money <= 100.0) ? 1.00
                  : (g_state.risk_money <= 1000.0)? 5.00
                  : 10.00;
      g_state.risk_money = MathMax(0.0, NormalizeDouble(g_state.risk_money - step, 2));
     }
   else
     { AdjustLots(-1); }
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickEntryUp(void)
  {
   AdjustEntry(+1);
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickEntryDn(void)
  {
   AdjustEntry(-1);
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickTPUp(void)
  {
   AdjustDistance(g_state.tp_points, +1);
   ClearMarketPriceTargets();
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickTPDn(void)
  {
   AdjustDistance(g_state.tp_points, -1);
   ClearMarketPriceTargets();
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickSLUp(void)
  {
   AdjustDistance(g_state.sl_points, +1);
   ClearMarketPriceTargets();
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickSLDn(void)
  {
   AdjustDistance(g_state.sl_points, -1);
   ClearMarketPriceTargets();
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickSell(void)
  { HandleOrderSelection(ACTION_SELL); }

void CLotForgePanel::OnClickBuy(void)
  { HandleOrderSelection(ACTION_BUY); }

void CLotForgePanel::OnClickSellPending(void)
  { HandleOrderSelection(ACTION_SELL_PENDING); }

void CLotForgePanel::OnClickBuyPending(void)
  { HandleOrderSelection(ACTION_BUY_PENDING); }

void CLotForgePanel::OnClickCancel(void)
  {
   QueueUiCommand(UI_CMD_CANCEL);
  }

void CLotForgePanel::OnClickSend(void)
  {
   SyncEditableFieldsToState();
   MarkPreviewDirty();
   g_ui.refresh_values = true;
   QueueUiCommand(UI_CMD_SEND);
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickBE                                      |
//|  BE manual: move SL para entrada + offset de proteção.            |
//|  Filtra por símbolo atual e magic do EA.                          |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickBE(void)
  { QueueUiCommand(UI_CMD_MANUAL_BE); }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickTrailing                                |
//|  Arma o trailing na posição atual do símbolo.                     |
//|  O trailing só atua efetivamente quando o BE estiver ativo.       |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickTrailing(void)
  { QueueUiCommand(UI_CMD_MANUAL_TRAILING); }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickAutoBE                                  |
//|  Toggles g_state.break_even_enabled and refreshes checkbox UI.   |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickAutoBE(void)
  { QueueUiCommand(UI_CMD_TOGGLE_AUTO_BE); }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickAutoTrailing                            |
//|  Toggles g_state.trailing_stop_enabled and refreshes checkbox.   |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickAutoTrailing(void)
  { QueueUiCommand(UI_CMD_TOGGLE_AUTO_TRAILING); }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: OnClickAlgoTrading                             |
//|  Toggle do Algo Trading — ativa/desativa pipeline completo de     |
//|  gestão automática: Auto BE → Parcial → Trailing pós-BE.          |
//+------------------------------------------------------------------+

void CLotForgePanel::OnClickAlgoTrading(void)
  { QueueUiCommand(UI_CMD_TOGGLE_ALGO_TRADING); }

void CLotForgePanel::OnEndEditPrimary(void)
  {
   double val;
   string text = m_EdtPrimary.Text();
   if(ParseDoubleText(text, val))
     {
      if(g_state.risk_mode == RISK_MODE_PERCENT)
         g_state.risk_percent = MathMax(0.0, val);
      else if(g_state.risk_mode == RISK_MODE_MONEY)
         g_state.risk_money = MathMax(0.0, NormalizeDouble(val, 2));
      else
         g_state.lots = NormalizeVolumeValue(val);
     }
   EndActiveEdit();
   QueueUiRefresh();
  }

void CLotForgePanel::OnEndEditEntry(void)
  {
   double val;
   if(ParseDoubleText(m_EdtEntry.Text(), val))
      g_state.entry_price = (val <= 0.0) ? 0.0 : NormalizePriceValue(val);
   EndActiveEdit();
   QueueUiRefresh();
  }

void CLotForgePanel::OnEndEditTP(void)
  {
   double val;
   if(ParseDoubleText(m_EdtTP.Text(), val))
      g_state.tp_points = MathMax(0.0, MathRound(val));
   ClearMarketPriceTargets();
   EndActiveEdit();
   QueueUiRefresh();
  }

void CLotForgePanel::OnEndEditSL(void)
  {
   double val;
   if(ParseDoubleText(m_EdtSL.Text(), val))
      g_state.sl_points = MathMax(0.0, MathRound(val));
   ClearMarketPriceTargets();
   EndActiveEdit();
   QueueUiRefresh();
  }


//+------------------------------------------------------------------+
//|  HandleOrderSelection (free function — uses g_panel)             |
//+------------------------------------------------------------------+

void HandleOrderSelection(const TradePanelAction action)
  {
   QueueUiOrderSelection(action);
  }

void QueueUiRefresh(const bool refresh_values,
                    const bool refresh_preview,
                    const bool redraw)
  {
   if(g_state.edit_in_progress)
      g_panel.EndActiveEdit();

   if(refresh_values)  g_ui.refresh_values = true;
   if(refresh_preview)
     {
      MarkPreviewDirty();
      g_ui.refresh_preview = true;
     }
   if(redraw)          g_ui.redraw = true;
  }

void QueueUiCommand(const UiDispatchCommand command)
  {
   if(g_state.edit_in_progress)
      g_panel.EndActiveEdit();

   g_ui.command = command;
   g_ui.redraw  = true;
  }

void QueueUiOrderSelection(const TradePanelAction action)
  {
   if(g_state.edit_in_progress)
      g_panel.EndActiveEdit();

   MarkPreviewDirty();
   g_ui.has_order_selection    = true;
   g_ui.selected_action        = action;
   g_ui.refresh_action_buttons = true;
   g_ui.refresh_values         = true;
   g_ui.refresh_preview        = true;
   g_ui.redraw                = true;
  }

void ProcessUiCancel()
  {
   g_status_sticky     = false;
   g_state.action      = ACTION_NONE;
   g_state.entry_price = 0.0;
   ClearMarketPriceTargets();
   g_state.active_edit = EDIT_TARGET_NONE;
   g_state.edit_in_progress = false;
   g_state.editing_object   = EDIT_TARGET_NONE;
   SyncUiInteractionState();
   SetStatus("Cancelado. Selecione o tipo de ordem.");
   g_ui.refresh_action_buttons = true;
   g_ui.refresh_values         = true;
   g_ui.clear_preview          = true;
  }

void ProcessUiSend()
  {
   TradeParams plan;
   string build_reason;
   string validation_msg;

   bool built = BuildTradePlan(plan, build_reason);
   if(!built)
     {
      SetStatus(build_reason != "" ? build_reason : "Erro: plano inválido.", true);
      return;
     }

   bool valid_plan = ValidateTradeRequest(plan, validation_msg);
   if(!valid_plan)
     {
      SetStatus(validation_msg, true);
      return;
     }

   bool sent = SendSelectedOrder(plan);
   g_ui.refresh_values = true;

   if(sent)
     {
      g_ui.refresh_action_buttons = true;
      g_ui.clear_preview          = true;
     }
  }

void ProcessUiManualBreakEven()
  {
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicNumber && magic != 0) continue;

      found = true;
      TryManualBreakEven(t);
      return;
     }

   if(!found)
      SetStatus("Nenhuma posição gerenciável aberta no símbolo atual.", true);
  }

void ProcessUiManualTrailing()
  {
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicNumber && magic != 0) continue;
      found = true;

      EnsureManagedState(t);
      int idx = FindManagedIndex(t);
      if(idx >= 0)
        {
         g_managed_trades[idx].trailing_armed = true;
         if(InpTrailingRequiresBE && !g_managed_trades[idx].be_applied)
            SetStatus("Trailing armado. Aguardando BE ativo para atuar.", true);
         else
            SetStatus("Trailing armado e ativo.", true);
        }
      return;
     }

   if(!found)
      SetStatus("Nenhuma posição gerenciável aberta no símbolo atual.", true);
  }

void ProcessUiToggleAutoBE()
  {
   g_state.break_even_enabled = !g_state.break_even_enabled;
   string msg = g_state.break_even_enabled
                ? "Auto BE ativado."
                : "Auto BE desativado.";
   SetStatus(msg);
   g_ui.refresh_be_trailing_buttons = true;
  }

void ProcessUiToggleAutoTrailing()
  {
   g_state.trailing_stop_enabled = !g_state.trailing_stop_enabled;
   g_ui.refresh_be_trailing_buttons = true;

   if(g_state.trailing_stop_enabled)
     {
      int armed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic != InpMagicNumber && magic != 0) continue;
         EnsureManagedState(t);
         int idx = FindManagedIndex(t);
         if(idx >= 0)
           {
            SyncProtectionState(idx);
            g_managed_trades[idx].trailing_armed = true;
            armed++;
           }
        }
      if(armed > 0)
         SetStatus(StringFormat("Auto Trailing ativado — %d posição(ões) armada(s).", armed));
      else
         SetStatus("Auto Trailing ativado.");
     }
   else
     {
      SetStatus("Auto Trailing desativado.");
     }
  }

void ProcessUiToggleAlgoTrading()
  {
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      SetStatus("Terminal desconectado.", true);
      g_ui.refresh_be_trailing_buttons = true;
      return;
     }

   bool term_allowed = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool ea_allowed   = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);

   g_algo_trading_enabled          = !g_algo_trading_enabled;
   g_state.algo_trading_ui_enabled = g_algo_trading_enabled;
   g_ui.refresh_be_trailing_buttons = true;

   if(!g_algo_trading_enabled)
     {
      SetStatus("Algo Trading desativado.", true);
      return;
     }

   if(!term_allowed)
     {
      SetStatus("Algo Trading ativado — mas AutoTrading está DESLIGADO no terminal!", true);
     }
   else if(!ea_allowed)
     {
      SetStatus("Algo Trading ativado — mas EA sem permissão de trade (verifique propriedades).", true);
     }
   else
     {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic != InpMagicNumber && magic != 0) continue;
         EnsureManagedState(t);
         int idx = FindManagedIndex(t);
         if(idx >= 0)
           {
            g_managed_trades[idx].algo_managed   = true;
            g_managed_trades[idx].trailing_armed = true;
            count++;
           }
        }
      if(count > 0)
         SetStatus(StringFormat("Algo Trading ON — %d posição(ões) no pipeline (BE→Parcial→Trailing).", count), true);
      else
         SetStatus("Algo Trading ON — aguardando próxima posição.", true);
     }

   Print("[ALGO] g_algo_trading_enabled=", g_algo_trading_enabled,
         "  TERMINAL_TRADE_ALLOWED=", term_allowed,
         "  MQL_TRADE_ALLOWED=", ea_allowed);
  }

void ProcessUiDispatch()
  {
   bool has_work = g_ui.has_order_selection ||
                   g_ui.command != UI_CMD_NONE ||
                   g_ui.refresh_values ||
                   g_ui.refresh_action_buttons ||
                   g_ui.refresh_be_trailing_buttons ||
                   g_ui.refresh_preview ||
                   g_ui.clear_preview ||
                   g_ui.redraw;
   if(!has_work) return;

   if(g_ui.has_order_selection)
     {
      TradePanelAction action = g_ui.selected_action;
      g_status_sticky = false;
      g_state.action = action;
      if(IsMarketAction(action))
        {
         g_state.entry_price = 0.0;
         ArmMarketPriceTargetsFromCurrentPoints();
        }
      else if(IsPendingAction(action))
        {
         ClearMarketPriceTargets();
         EnsurePendingEntry();
        }
      string lbl = EffectiveActionLabel(action, g_state.entry_price);
      SetStatus("Ação: " + lbl + ". Configure e clique Send.");
     }

   switch(g_ui.command)
     {
      case UI_CMD_CANCEL:               ProcessUiCancel(); break;
      case UI_CMD_SEND:                 ProcessUiSend(); break;
      case UI_CMD_MANUAL_BE:            ProcessUiManualBreakEven(); break;
      case UI_CMD_MANUAL_TRAILING:      ProcessUiManualTrailing(); break;
      case UI_CMD_TOGGLE_AUTO_BE:       ProcessUiToggleAutoBE(); break;
      case UI_CMD_TOGGLE_AUTO_TRAILING: ProcessUiToggleAutoTrailing(); break;
      case UI_CMD_TOGGLE_ALGO_TRADING:  ProcessUiToggleAlgoTrading(); break;
      default:                          break;
     }

   if(g_ui.refresh_action_buttons)
      g_panel.RefreshActionButtons();
   else if(g_ui.refresh_be_trailing_buttons)
      g_panel.RefreshBETrailingButtons();

   if(g_ui.refresh_values)
      g_panel.RefreshValues();

   if(g_ui.clear_preview)
      DeletePreviewObjects();
   else if(g_ui.refresh_preview)
      UpdatePreview(false);

   if(g_ui.redraw)
      RequestChartRedraw();

   FlushPendingChartRedraw();

   g_ui.Reset();
  }
