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
ON_EVENT(ON_CLICK, m_BtnTrailing,     OnClickTrailing)
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
                                        CButton &btn_up, CButton &btn_dn)
  {
   // Solid label block: white background, gray text — matches V1.07 style
   if(!lbl.Create(m_chart_id, m_name + "_lbl_" + lbl_text, m_subwin,
      x, y, x + LABEL_W, y + ROW_H)) return false;
   lbl.Text(lbl_text);
   lbl.FontSize(9);
   lbl.Color(C'110,110,110');      // ghosted gray text
   lbl.ColorBackground(clrWhite);  // solid white block
   if(!Add(lbl)) return false;

   int ex = x + LABEL_W;
   if(!edt.Create(m_chart_id, m_name + "_edt_" + lbl_text, m_subwin,
      ex, y, ex + EDIT_W, y + EDIT_H)) return false;
   edt.Text(edt_text);
   edt.FontSize(9);
   if(!Add(edt)) return false;

   int sx = ex + EDIT_W + 1;
   if(!btn_up.Create(m_chart_id, m_name + "_up_" + lbl_text, m_subwin,
      sx, y, sx + SPIN_W, y + SPIN_H)) return false;
   btn_up.Text("+");
   btn_up.FontSize(7);
   if(!Add(btn_up)) return false;

   if(!btn_dn.Create(m_chart_id, m_name + "_dn_" + lbl_text, m_subwin,
      sx, y + SPIN_H, sx + SPIN_W, y + ROW_H)) return false;
   btn_dn.Text("-");
   btn_dn.FontSize(7);
   if(!Add(btn_dn)) return false;

   return true;
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: CreateRiskModeGroup                            |
//|  Creates: [RiskMode btn][Edit][▲][▼]                             |
//+------------------------------------------------------------------+

bool CLotForgePanel::CreateRiskModeGroup(const int x, const int y)
  {
   string mode_text = (g_state.risk_mode == RISK_MODE_PERCENT) ? "Risk%" : "Lots";

   if(!m_BtnRiskMode.Create(m_chart_id, m_name + "_btn_riskmode", m_subwin,
      x, y, x + LABEL_W, y + ROW_H)) return false;
   m_BtnRiskMode.Text(mode_text);
   m_BtnRiskMode.FontSize(9);
   m_BtnRiskMode.ColorBackground(clrWhite);      // v1.07: flat label look, white like edit
   m_BtnRiskMode.Color(clrBlack);                // dark text on white
   if(!Add(m_BtnRiskMode)) return false;

   int ex = x + LABEL_W;
   string val_text = (g_state.risk_mode == RISK_MODE_PERCENT)
                     ? FormatPercent(g_state.risk_percent)
                     : FormatLots(g_state.lots);
   if(!m_EdtPrimary.Create(m_chart_id, m_name + "_edt_primary", m_subwin,
      ex, y, ex + EDIT_W, y + EDIT_H)) return false;
   m_EdtPrimary.Text(val_text);
   m_EdtPrimary.FontSize(9);
   if(!Add(m_EdtPrimary)) return false;

   int sx = ex + EDIT_W + 2;
   if(!m_BtnPrimaryUp.Create(m_chart_id, m_name + "_up_primary", m_subwin,
      sx, y, sx + SPIN_W, y + SPIN_H)) return false;
   m_BtnPrimaryUp.Text("+");
   m_BtnPrimaryUp.FontSize(7);
   if(!Add(m_BtnPrimaryUp)) return false;

   if(!m_BtnPrimaryDn.Create(m_chart_id, m_name + "_dn_primary", m_subwin,
      sx, y + SPIN_H, sx + SPIN_W, y + ROW_H)) return false;
   m_BtnPrimaryDn.Text("-");
   m_BtnPrimaryDn.FontSize(7);
   if(!Add(m_BtnPrimaryDn)) return false;

   return true;
  }

//+------------------------------------------------------------------+
//|  CLotForgePanel :: CreatePanel                                    |
//|                                                                  |
//|  Compact two-column layout:                                      |
//|  Row 1: [Lots/Risk%][val][±]  [Entry][val][±]                   |
//|  Row 2: [TP][val][±]          [SL][val][±]                       |
//|  Row 3: [Sell]                [Buy]                              |
//|  Row 4: [Sell Pending]        [Buy Pending]                      |
//|  Row 5: [BE ■amber]           [Trailing ■purple]                 |
//|  Row 6: [☐ Auto BE]          [☐ Auto Trailing]  (checkboxes)    |
//|  Row 7: [Cancel]              [Send]             (always last)   |
//+------------------------------------------------------------------+

bool CLotForgePanel::CreatePanel(const long chart, const string name,
                                  const int subwin, const int x1, const int y1)
  {
   int x2 = x1 + PANEL_W;
   int y2 = y1 + PANEL_H;
   if(!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2))
      return false;

   // Compute layout metrics from the REAL client area reported by CAppDialog.
   // CAppDialog's chrome (outer frame + title bar border insets) makes the
   // usable client narrower than PANEL_W.  Using ClientAreaWidth() here is
   // the correct approach — it reflects the actual drawable rectangle so the
   // right column never gets clipped regardless of DPI or border thickness.
   m_content_w = ClientAreaWidth() - 6;   // 3px margin each side inside client area
   m_col_w     = (m_content_w - COL_GAP) / 2;

   int cx = 3;
   int cy = 2;

   // ── Row 1: RiskMode group + Entry group ────────────────────────
   if(!CreateRiskModeGroup(cx, cy)) return false;
   int rx = cx + m_col_w + COL_GAP;
   if(!CreateInlineGroup(rx, cy,
         m_LblEntry, "Entry",
         m_EdtEntry, g_state.entry_price <= 0.0 ? "0" : FormatPrice(g_state.entry_price),
         m_BtnEntryUp, m_BtnEntryDn)) return false;
   cy += ROW_H + ROW_GAP;

   // ── Row 2: TP group + SL group ─────────────────────────────────
   if(!CreateInlineGroup(cx, cy,
         m_LblTP, "TP",
         m_EdtTP, FormatPoints(g_state.tp_points),
         m_BtnTPUp, m_BtnTPDn)) return false;
   if(!CreateInlineGroup(rx, cy,
         m_LblSL, "SL",
         m_EdtSL, FormatPoints(g_state.sl_points),
         m_BtnSLUp, m_BtnSLDn)) return false;
   cy += ROW_H + SECTION_GAP;

   // ── Comment ────────────────────────────────────────────────────
   // ── Action buttons: 2-column grid ──────────────────────────────
   int btn_w = (m_content_w - 4) / 2;

   if(!m_BtnSell.Create(chart, name + "_btn_sell", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnSell.Text("Sell");
   m_BtnSell.ColorBackground(CLR_SELL_BG);
   m_BtnSell.Color(clrWhite);
   m_BtnSell.ColorBorder(C'210,50,40');
   if(!Add(m_BtnSell)) return false;

   if(!m_BtnBuy.Create(chart, name + "_btn_buy", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnBuy.Text("Buy");
   m_BtnBuy.ColorBackground(CLR_BUY_BG);
   m_BtnBuy.Color(clrWhite);
   m_BtnBuy.ColorBorder(C'0,180,0');
   if(!Add(m_BtnBuy)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   if(!m_BtnSellPending.Create(chart, name + "_btn_sellp", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnSellPending.Text("Sell Pending");
   m_BtnSellPending.ColorBackground(CLR_SELL_BG);
   m_BtnSellPending.Color(clrWhite);
   m_BtnSellPending.ColorBorder(C'210,50,40');
   if(!Add(m_BtnSellPending)) return false;

   if(!m_BtnBuyPending.Create(chart, name + "_btn_buyp", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnBuyPending.Text("Buy Pending");
   m_BtnBuyPending.ColorBackground(CLR_BUY_BG);
   m_BtnBuyPending.Color(clrWhite);
   m_BtnBuyPending.ColorBorder(C'0,180,0');
   if(!Add(m_BtnBuyPending)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row: BE | Trailing ─────────────────────────────────────────
   //  BE is amber, Trailing is purple — visually distinct from trade-side buttons
   if(!m_BtnBE.Create(chart, name + "_btn_be", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnBE.Text("BE");
   m_BtnBE.ColorBackground(CLR_BE_BG);
   m_BtnBE.Color(clrWhite);
   m_BtnBE.ColorBorder(CLR_BE_BORDER);
   if(!Add(m_BtnBE)) return false;

   if(!m_BtnTrailing.Create(chart, name + "_btn_trail", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnTrailing.Text("Trailing");
   m_BtnTrailing.ColorBackground(CLR_TRAILING_BG);
   m_BtnTrailing.Color(clrWhite);
   m_BtnTrailing.ColorBorder(CLR_TRAILING_BORDER);
   if(!Add(m_BtnTrailing)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row: Auto BE | Auto Trailing (real toggle checkboxes) ──────
   //  CButton styled as checkbox: text shows [ ] / [✓], bg shows off/on color
   string chk_be_text   = g_state.break_even_enabled    ? "[✓] Auto BE"      : "[ ] Auto BE";
   string chk_trail_text= g_state.trailing_stop_enabled ? "[✓] Auto Trailing" : "[ ] Auto Trailing";

   // ── Row: Auto BE | Auto Trailing ─────────────────────────────
   //  v1.09: promoted to ACTION_BTN_H (28) for visual height consistency
   if(!m_ChkAutoBE.Create(chart, name + "_chk_autobe", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_ChkAutoBE.Text(chk_be_text);
   m_ChkAutoBE.FontSize(8);
   m_ChkAutoBE.ColorBackground(g_state.break_even_enabled ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_ChkAutoBE.Color(g_state.break_even_enabled ? clrWhite : clrBlack);
   m_ChkAutoBE.ColorBorder(C'130,140,160');
   if(!Add(m_ChkAutoBE)) return false;

   if(!m_ChkAutoTrailing.Create(chart, name + "_chk_autotrail", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_ChkAutoTrailing.Text(chk_trail_text);
   m_ChkAutoTrailing.FontSize(8);
   m_ChkAutoTrailing.ColorBackground(g_state.trailing_stop_enabled ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_ChkAutoTrailing.Color(g_state.trailing_stop_enabled ? clrWhite : clrBlack);
   m_ChkAutoTrailing.ColorBorder(C'130,140,160');
   if(!Add(m_ChkAutoTrailing)) return false;
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row: Algo Trading (full-width toggle row — same family as Auto BE/Trailing)
   {
    string algo_text = g_state.algo_trading_ui_enabled ? "[✓] Algo Trading" : "[ ] Algo Trading";
    if(!m_BtnAlgoTrading.Create(chart, name + "_btn_algo", subwin,
       cx, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
    m_BtnAlgoTrading.Text(algo_text);
    m_BtnAlgoTrading.FontSize(9);
    m_BtnAlgoTrading.ColorBackground(g_state.algo_trading_ui_enabled ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
    m_BtnAlgoTrading.Color(g_state.algo_trading_ui_enabled ? clrWhite : clrBlack);
    m_BtnAlgoTrading.ColorBorder(C'130,140,160');
    if(!Add(m_BtnAlgoTrading)) return false;
   }
   cy += ACTION_BTN_H + ACTION_BTN_ROW_GAP;

   // ── Row: Cancel | Send (always the final row) ──────────────────
   if(!m_BtnCancel.Create(chart, name + "_btn_cancel", subwin,
      cx, cy, cx + btn_w, cy + ACTION_BTN_H)) return false;
   m_BtnCancel.Text("Cancel");
   m_BtnCancel.ColorBackground(CLR_NEUTRAL_BG);
   m_BtnCancel.Color(clrBlack);
   if(!Add(m_BtnCancel)) return false;

   if(!m_BtnSend.Create(chart, name + "_btn_send", subwin,
      cx + btn_w + 4, cy, cx + m_content_w, cy + ACTION_BTN_H)) return false;
   m_BtnSend.Text("Send");
   m_BtnSend.ColorBackground(CLR_NEUTRAL_BG);
   m_BtnSend.Color(clrBlack);
   if(!Add(m_BtnSend)) return false;


   // ── Apply two-blue chrome AFTER all controls are added ─────────
   //  CAppDialog caption (title bar) is OBJ_EDIT named <n>Caption —
   //  not OBJ_RECTANGLE_LABEL. Colors applied here (post-Add) are
   //  safe from being reset by subsequent Add() calls.
   //    OBJ_RECTANGLE_LABEL <n>ClientBack → inner body (lighter blue)
   //    OBJ_RECTANGLE_LABEL <n>*          → outer frame (dark blue)
   //    OBJ_EDIT            <n>Caption    → title bar text strip (dark blue)
   //    OBJ_BUTTON          <n>Min/Close/Back → window controls (gray)
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
          // Caption bar (OBJ_EDIT) — dark blue background, white text
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
   string mode_text = (g_state.risk_mode == RISK_MODE_PERCENT) ? "Risk%" : "Lots";
   if(m_BtnRiskMode.Text() != mode_text) m_BtnRiskMode.Text(mode_text);

   string prim_text = (g_state.risk_mode == RISK_MODE_PERCENT)
                      ? FormatPercent(g_state.risk_percent)
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
   btn.ColorBorder(selected ? CLR_SELECTED_BORDER : base_clr);
  }

void CLotForgePanel::RefreshActionButtons(void)
  {
   ApplyActionStyle(m_BtnSell,        CLR_SELL_BG, g_state.action == ACTION_SELL);
   ApplyActionStyle(m_BtnBuy,         CLR_BUY_BG,  g_state.action == ACTION_BUY);
   ApplyActionStyle(m_BtnSellPending, CLR_SELL_BG, g_state.action == ACTION_SELL_PENDING);
   ApplyActionStyle(m_BtnBuyPending,  CLR_BUY_BG,  g_state.action == ACTION_BUY_PENDING);

   color cs = (g_state.action != ACTION_NONE) ? C'180,190,208' : CLR_NEUTRAL_BG;
   ApplyActionStyle(m_BtnCancel, cs, false);
   ApplyActionStyle(m_BtnSend,   cs, false);

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
   m_ChkAutoBE.Text(be_on ? "[✓] Auto BE" : "[ ] Auto BE");
   m_ChkAutoBE.ColorBackground(be_on ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_ChkAutoBE.Color(be_on ? clrWhite : clrBlack);

   // Auto Trailing checkbox
   bool trail_on = g_state.trailing_stop_enabled;
   m_ChkAutoTrailing.Text(trail_on ? "[✓] Auto Trailing" : "[ ] Auto Trailing");
   m_ChkAutoTrailing.ColorBackground(trail_on ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
   m_ChkAutoTrailing.Color(trail_on ? clrWhite : clrBlack);

   // Algo Trading toggle row
   bool algo_on = g_state.algo_trading_ui_enabled;
   m_BtnAlgoTrading.Text(algo_on ? "[✓] Algo Trading" : "[ ] Algo Trading");
   m_BtnAlgoTrading.ColorBackground(algo_on ? CLR_CHK_ON_BG : CLR_CHK_OFF_BG);
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
      return (g_state.risk_mode == RISK_MODE_PERCENT)
             ? EDIT_TARGET_RISK_PCT
             : EDIT_TARGET_LOTS;
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
   g_state.risk_mode = (g_state.risk_mode == RISK_MODE_LOTS)
                       ? RISK_MODE_PERCENT : RISK_MODE_LOTS;
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickPrimaryUp(void)
  {
   if(g_state.risk_mode == RISK_MODE_PERCENT)
     { g_state.risk_percent = NormalizeDouble(g_state.risk_percent + 0.25, 2); }
   else
     { AdjustLots(+1); }
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickPrimaryDn(void)
  {
   if(g_state.risk_mode == RISK_MODE_PERCENT)
     { g_state.risk_percent = MathMax(0.0, NormalizeDouble(g_state.risk_percent - 0.25, 2)); }
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
   ArmMarketPriceTargetsFromCurrentPoints();
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickTPDn(void)
  {
   AdjustDistance(g_state.tp_points, -1);
   ArmMarketPriceTargetsFromCurrentPoints();
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickSLUp(void)
  {
   AdjustDistance(g_state.sl_points, +1);
   ArmMarketPriceTargetsFromCurrentPoints();
   QueueUiRefresh();
  }

void CLotForgePanel::OnClickSLDn(void)
  {
   AdjustDistance(g_state.sl_points, -1);
   ArmMarketPriceTargetsFromCurrentPoints();
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
   double val;
   string text;

   text = m_EdtPrimary.Text();
   if(ParseDoubleText(text, val))
     {
      if(g_state.risk_mode == RISK_MODE_PERCENT)
         g_state.risk_percent = MathMax(0.0, val);
      else
         g_state.lots = NormalizeVolumeValue(val);
     }
   text = m_EdtEntry.Text();
   if(ParseDoubleText(text, val))
      g_state.entry_price = (val <= 0.0) ? 0.0 : NormalizePriceValue(val);
   text = m_EdtTP.Text();
   if(ParseDoubleText(text, val))
      g_state.tp_points = MathMax(0.0, MathRound(val));
   text = m_EdtSL.Text();
   if(ParseDoubleText(text, val))
      g_state.sl_points = MathMax(0.0, MathRound(val));
   if(IsMarketAction(g_state.action) &&
      (g_state.editing_object == EDIT_TARGET_TP || g_state.editing_object == EDIT_TARGET_SL))
      ArmMarketPriceTargetsFromCurrentPoints();
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
   ArmMarketPriceTargetsFromCurrentPoints();
   EndActiveEdit();
   QueueUiRefresh();
  }

void CLotForgePanel::OnEndEditSL(void)
  {
   double val;
   if(ParseDoubleText(m_EdtSL.Text(), val))
      g_state.sl_points = MathMax(0.0, MathRound(val));
   ArmMarketPriceTargetsFromCurrentPoints();
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
